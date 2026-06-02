#!/usr/bin/env bash
# ============================================================
# autonomy.sh — Autonomy Supervisor CLI (ClaudeOS v3.4.0)
#
# 登録プロジェクトを Goal/Release 到達まで自律再開させる supervisor を管理する。
# 各セッションは cron-launcher.sh 経由 (= claude TUI + 自律 + メール + 監視タブメタ)。
#
# 使い方:
#   autonomy.sh start  <project> [--duration N] [--force]   # supervisor 起動 (setsid 常駐)
#   autonomy.sh stop   <project> [--now]                    # グレースフル停止 (--now で即kill)
#   autonomy.sh status [project]                            # 状態表示 (省略時は全件)
#   autonomy.sh list                                        # 一覧
#
# 安全: 既定 OFF (明示 start するまで何も自走しない)。日次上限/Goal/Blocked で必ず停止。
#       supervisor 管理プロジェクトに cron 登録があると競合するため start 時に警告
#       (--force で続行可。推奨は項14 で当該 cron を削除)。
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"
# shellcheck source=lib/launcher-common.sh
source "$SCRIPT_DIR/../lib/launcher-common.sh"
# shellcheck source=lib/cron-manager.sh
source "$SCRIPT_DIR/../lib/cron-manager.sh"
# shellcheck source=lib/supervisor.sh
source "$SCRIPT_DIR/../lib/supervisor.sh"

SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# au__has_cron <project> — 当該プロジェクトの CLAUDEOS cron エントリがあれば 0
au__has_cron() {
  cron__list 2>/dev/null | awk -F'|' -v p="$1" '$2==p {f=1} END{exit !f}'
}

# au__start <project> [--duration N] [--force]
au__start() {
  local project="" duration="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --duration) duration="$2"; shift 2 ;;
      --force)    force=1; shift ;;
      --*)        log_error "start: 不明な引数: $1"; return 1 ;;
      *)          project="$1"; shift ;;
    esac
  done
  [[ -n "$project" ]] || { log_error "start: <project> は必須"; return 1; }
  launcher__project_exists "$project" || { log_error "プロジェクトが存在しません: $(launcher__project_dir "$project")"; return 1; }
  [[ -f "$SUP_CRON_LAUNCHER" ]] || { log_error "cron-launcher.sh が見つかりません: $SUP_CRON_LAUNCHER"; return 1; }

  if sup__is_running "$project"; then
    log_warn "既に supervisor 稼働中: $project (pid=$(sup__get "$project" pid 0))"
    return 0
  fi

  # cron 競合チェック (承認方針: supervisor 管理中は cron 登録を外す)
  if au__has_cron "$project"; then
    if (( force )); then
      log_warn "cron 登録ありだが --force のため続行: $project (二重起動に注意)"
    else
      log_error "cron 登録が残っています: $project"
      log_info  "  競合回避のため項14で当該 cron を削除してから start するか、--force を付けてください"
      return 1
    fi
  fi

  local runner logf
  mkdir -p "$SUP_DIR"; chmod 700 "$SUP_DIR" 2>/dev/null || true
  rm -f "$(sup__stop_file "$project")"   # 起動前に古い stop フラグをクリア (fresh start)
  logf="$SUP_DIR/$(ccsu_safe_name "$project").log"
  if has_cmd setsid; then runner=setsid; else runner=nohup; fi
  "$runner" bash "$SELF" __run "$project" ${duration:+"$duration"} </dev/null >>"$logf" 2>&1 &
  disown 2>/dev/null || true

  # 起動確認 (state ファイルが書かれるまで軽く待つ)
  local i
  for ((i = 0; i < 10; i++)); do
    [[ -f "$(sup__state_file "$project")" ]] && break
    sleep 0.2
  done
  log_ok "supervisor 起動: $project"
  log_info "  状態: bash bin/autonomy.sh status $project   ログ: $logf"
  log_info "  停止: bash bin/autonomy.sh stop $project    (--now で即停止)"
}

# au__stop <project> [--now]
au__stop() {
  local project="" now=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --now) now=1; shift ;;
      --*)   log_error "stop: 不明な引数: $1"; return 1 ;;
      *)     project="$1"; shift ;;
    esac
  done
  [[ -n "$project" ]] || { log_error "stop: <project> は必須"; return 1; }

  if ! sup__is_running "$project" && [[ ! -f "$(sup__state_file "$project")" ]]; then
    log_warn "supervisor は稼働していません: $project"
    return 0
  fi
  sup__request_stop "$project"
  log_ok "停止要求: $project (現セッション終了後に再起動を止めます)"

  if (( now )); then
    local pid safe; pid="$(sup__get "$project" pid 0)"; safe="$(ccsu_safe_name "$project")"
    [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )) && kill "$pid" 2>/dev/null || true
    "$SUP_TMUX_BIN" kill-session -t "claudeos-$safe" 2>/dev/null || true
    "$SUP_TMUX_BIN" kill-session -t "_keeper_$safe" 2>/dev/null || true
    log_info "  --now: supervisor と現セッションを即停止しました"
  fi
}

# au__render <project> — 1 プロジェクトの状態を 1 行で
au__render() {
  local project="$1" f status restarts minutes reason alive
  f="$(sup__state_file "$project")"
  [[ -f "$f" ]] || { printf '  %-26s %s(状態ファイルなし)%s\n' "$project" "$C_GRAY" "$C_RESET"; return 0; }
  status="$(json_get "$f" '.status' '?')"
  restarts="$(json_get "$f" '.restarts_today' '0')"
  minutes="$(json_get "$f" '.minutes_today' '0')"
  reason="$(json_get "$f" '.last_reason' '')"
  if sup__is_running "$project"; then alive="● 稼働"; else alive="○ 停止"; fi
  printf '  %-26s %-8s %-10s restarts=%-3s minutes=%-4s %s\n' \
    "$project" "$alive" "$status" "$restarts" "$minutes" "$reason"
}

# au__status [project]
au__status() {
  if [[ -n "${1:-}" ]]; then au__render "$1"; return 0; fi
  au__list
}

# au__list — 全 supervisor を列挙
au__list() {
  printf '  %s● Autonomy Supervisor 一覧:%s\n' "$C_GREEN" "$C_RESET"
  local found=0 f project
  if [[ -d "$SUP_DIR" ]]; then
    for f in "$SUP_DIR"/*.json; do
      [[ -f "$f" ]] || continue
      found=1
      project="$(json_get "$f" '.project' "$(basename "$f" .json)")"
      au__render "$project"
    done
  fi
  (( found == 0 )) && printf '  %s(supervisor なし)%s\n' "$C_GRAY" "$C_RESET"
  return 0
}

main() {
  require_cmd jq
  case "${1:-}" in
    start)   shift; au__start "$@" ;;
    stop)    shift; au__stop "$@" ;;
    status)  shift; au__status "$@" ;;
    list)    au__list ;;
    __run)   shift; sup__loop "$@" ;;   # setsid から呼ばれる本体
    ""|--help|-h)
      printf 'Usage: autonomy.sh start|stop|status|list <project> [opts]\n'
      printf '  start  <project> [--duration N] [--force]\n'
      printf '  stop   <project> [--now]\n'
      printf '  status [project]\n'
      printf '  list\n' ;;
    *) log_error "不明なサブコマンド: $1 (start|stop|status|list)"; return 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
