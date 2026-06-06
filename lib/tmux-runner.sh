#!/usr/bin/env bash
# ============================================================
# tmux-runner.sh — ClaudeCode の tmux 実行エンジン (Linux native)
#
# 役割: 手動起動 (bin/start-claude.sh) から ClaudeCode を tmux セッションで
#       フォアグラウンド/バックグラウンド起動する。cron-launcher.sh と同じ
#       命名規則 (claudeos-<safe>) と pipe-pane ログ方式を共有するため、
#       メニュー項13(ログ監視)/項15(状態監視) が cron/手動どちらのセッションも
#       区別なく扱える。
#
# 移植元: Claude/templates/linux/cron-launcher.sh の tmux ブロック (L307-345)
#         + Start-ClaudeCode.ps1 のローカル起動 (SSH 分岐は廃止)
#
# 設計差分 (cron vs 手動):
#   - cron : keeper + wait-for で同期実行 (タイムアウト管理)
#   - 手動 : foreground=attach / background=detached で即復帰 (待たない)
# ============================================================

[[ -n "${_CCSU_TMUX_LOADED:-}" ]] && return 0
_CCSU_TMUX_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config-loader.sh"

# tmux/claude コマンド (テストでスタブ差し替え可)
TMUX_BIN="${CCSU_TMUX_BIN:-tmux}"
CLAUDE_BIN="${CCSU_CLAUDE_BIN:-claude}"

# レポートメール (cron-launcher.sh と同一の report-and-mail.py を共有)
CCSU_REPORT_SCRIPT="${CLAUDEOS_REPORT_SCRIPT:-$CCSU_HOME/report-and-mail.py}"

# tmux__session_name <project> — セッション名 (cron-launcher.sh と同一規則)
tmux__session_name() { printf 'claudeos-%s' "$(ccsu_safe_name "$1")"; }

# tmux__is_running <project> — 起動中なら 0
tmux__is_running() { "$TMUX_BIN" has-session -t "$(tmux__session_name "$1")" 2>/dev/null; }

# tmux__status — 全 claudeos-* セッションを列挙 (cron/手動 両方)
tmux__status() {
  local out
  out="$("$TMUX_BIN" ls 2>/dev/null | grep '^claudeos-' || true)"
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; else printf '(実行中の ClaudeOS セッションなし)\n'; fi
}

# tmux__attach <project> — セッションに接続
tmux__attach() {
  local s; s="$(tmux__session_name "$1")"
  tmux__is_running "$1" || { log_warn "セッションが見つかりません: $s"; return 1; }
  "$TMUX_BIN" attach -t "$s"
}

# tmux__stop <project> — セッションを停止 (keeper も落とす)
tmux__stop() {
  local safe s keeper
  safe="$(ccsu_safe_name "$1")"; s="claudeos-$safe"; keeper="_keeper_$safe"
  if "$TMUX_BIN" has-session -t "$s" 2>/dev/null; then
    "$TMUX_BIN" kill-session -t "$s" 2>/dev/null || true
    "$TMUX_BIN" kill-session -t "$keeper" 2>/dev/null || true
    log_ok "停止: $s"
  else
    log_warn "セッションが見つかりません: $s"
    return 1
  fi
}

# ------------------------------------------------------------
# tmux__send_report <sid> <log> <status> <start> <end> <dur_min> <project>
#   手動セッションの終了レポートメールを送信 (cron-launcher.sh の finalize と同一の
#   report-and-mail.py を共有)。CLAUDEOS_EMAIL_ENABLED=1 かつ python3 + スクリプト
#   存在時のみ送信。失敗しても全体は成功扱い (副次機能)。
# ------------------------------------------------------------
tmux__send_report() {
  local sid="$1" log="$2" status="$3" start="$4" end="$5" dur="$6" project="$7"
  [[ "${CLAUDEOS_EMAIL_ENABLED:-0}" == "1" ]] || return 0
  [[ "${CLAUDEOS_MANUAL_EMAIL:-1}" == "1" ]]   || return 0   # 手動メールだけ無効化する余地
  has_cmd python3            || { log_warn "python3 不在: レポートメール skip"; return 0; }
  [[ -f "$CCSU_REPORT_SCRIPT" ]] || { log_warn "report-and-mail.py 不在: skip ($CCSU_REPORT_SCRIPT)"; return 0; }
  python3 "$CCSU_REPORT_SCRIPT" \
    --session "$sid" --log "$log" --status "$status" \
    --start "$start" --end "$end" --duration-min "$dur" \
    --project "$project" --sessions-dir "$CCSU_HOME/sessions" \
    >>"$log" 2>&1 || log_warn "レポートメール送信に失敗 (詳細はログ: $log)"
  return 0
}

# ------------------------------------------------------------
# tmux__report_watcher <session> <sid> <project> <dur_min> <start_iso> <log>
#   セッション終了まで待機し、終了後にレポートメールを送る (setsid 経由で常駐)。
#   status 推定: 経過が予定 duration にほぼ達していれば timeout、それ以外は completed。
# ------------------------------------------------------------
tmux__report_watcher() {
  local session="$1" sid="$2" project="$3" dur="$4" start="$5" log="$6"
  local interval="${CCSU_REPORT_POLL_SEC:-30}" start_epoch now elapsed status end
  start_epoch="$(date +%s)"
  while "$TMUX_BIN" has-session -t "$session" 2>/dev/null; do sleep "$interval"; done
  now="$(date +%s)"; elapsed=$(( now - start_epoch )); end="$(date -Iseconds)"
  if [[ "$dur" =~ ^[0-9]+$ ]] && (( dur > 0 )) && (( elapsed >= dur * 60 - interval )); then
    status="timeout"
  else
    status="completed"
  fi
  tmux__send_report "$sid" "$log" "$status" "$start" "$end" "$dur" "$project"
}

# ------------------------------------------------------------
# tmux_run <project> <duration-min> <mode>
#   mode: foreground (既定, attach) | background (detached, 即復帰)
#   - PROJECTS_BASE/<project> に cd して tmux で claude を起動
#   - pipe-pane で TUI 制御シーケンス除去後のログを ~/.claudeos/logs へ
#   - CLAUDEOS_EMAIL_ENABLED=1 時は終了レポートメール用 watcher を常駐させる
# ------------------------------------------------------------
tmux_run() {
  local project="$1" duration_min="${2:-300}" mode="${3:-foreground}"
  require_cmd "$TMUX_BIN"
  require_cmd "$CLAUDE_BIN"

  local safe session dur_sec base project_dir log_file stamp
  safe="$(ccsu_safe_name "$project")"
  session="claudeos-$safe"
  dur_sec=$((duration_min * 60))
  base="$(config_projects_dir)"
  project_dir="$base/$project"
  [[ -d "$project_dir" ]] || { log_error "プロジェクトディレクトリが存在しません: $project_dir"; return 1; }

  # 既に起動中なら再起動せず案内
  if "$TMUX_BIN" has-session -t "$session" 2>/dev/null; then
    log_warn "既に起動中です: $session"
    [[ "$mode" == "foreground" ]] && "$TMUX_BIN" attach -t "$session"
    return 0
  fi

  mkdir -p "$CCSU_HOME/logs"
  stamp="$(date +%Y%m%d-%H%M%S)"
  log_file="$CCSU_HOME/logs/manual-${stamp}-${safe}.log"

  # hooks 環境変数 (cron-launcher.sh L153 と同一)
  export CLAUDEOS_HOOKS_DIR="$project_dir/.claude/claudeos/scripts/hooks"
  export CLAUDE_PROJECT="$project"

  # Copy latest START_PROMPT template to project before launch (always overwrite)
  local _tmpl_sp="$CCSU_ROOT/Claude/templates/claude/START_PROMPT.md"
  if [[ -f "$_tmpl_sp" ]]; then
    mkdir -p "$project_dir/.claude"
    cp "$_tmpl_sp" "$project_dir/.claude/START_PROMPT.md"
  fi

  # START_PROMPT.md があれば claude に渡す (cat 展開を tmux コマンド内で実行)
  local claude_cmd
  if [[ -f "$project_dir/.claude/START_PROMPT.md" ]]; then
    claude_cmd="timeout ${dur_sec}s $CLAUDE_BIN --dangerously-skip-permissions \"\$(cat '$project_dir/.claude/START_PROMPT.md')\""
  else
    claude_cmd="timeout ${dur_sec}s $CLAUDE_BIN --dangerously-skip-permissions"
  fi

  # tmux セッション起動 (detached)。-c で作業ディレクトリ指定
  # -n "$safe" で安定ウィンドウ名を付与 (ライブ監視タブ monitor-sessions.sh の link 照合用)
  "$TMUX_BIN" new-session -d -s "$session" -n "$safe" -c "$project_dir" -x 220 -y 50 "$claude_cmd"
  # 監視タブ用メタデータ (cron-launcher.sh と同一規則。best-effort)
  "$TMUX_BIN" set-option -w -t "$session:0" automatic-rename off 2>/dev/null || true
  "$TMUX_BIN" set-option -w -t "$session:0" @ccsu_project "$project" 2>/dev/null || true
  "$TMUX_BIN" set-option -w -t "$session:0" @ccsu_duration_min "$duration_min" 2>/dev/null || true

  # pipe-pane: TUI 制御シーケンスを除去してログへ (cron-launcher.sh L333 と同一 sed)
  "$TMUX_BIN" pipe-pane -t "$session" -o \
    "sed 's/.*\r//; s/\x1b\][^\x07]*\x07//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b.//g' >> '$log_file'" 2>/dev/null || \
    log_warn "pipe-pane に失敗 (ログ可視化なし): $log_file"

  # 終了レポートメール watcher (CLAUDEOS_EMAIL_ENABLED=1 時のみ)。
  # setsid で常駐させ、端末を閉じてもセッション終了まで生存させる。
  # lib 自身を __watch サブコマンドで再実行する (関数を setsid に直接渡せないため)。
  if [[ "${CLAUDEOS_EMAIL_ENABLED:-0}" == "1" && "${CLAUDEOS_MANUAL_EMAIL:-1}" == "1" ]]; then
    local sid start_iso self runner
    sid="manual-${stamp}-${safe}"
    start_iso="$(date -Iseconds)"
    self="${BASH_SOURCE[0]}"
    if has_cmd setsid; then runner=setsid; else runner=nohup; fi
    "$runner" bash "$self" __watch "$session" "$sid" "$project" "$duration_min" "$start_iso" "$log_file" \
      </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    log_info "  メール: 終了時にレポート送信 (CLAUDEOS_EMAIL_ENABLED=1)"
  fi

  if [[ "$mode" == "foreground" ]]; then
    log_info "フォアグラウンド起動: $session (Ctrl-b d でデタッチしても BG 継続)"
    "$TMUX_BIN" attach -t "$session"
  else
    log_ok "バックグラウンド起動: $session"
    log_info "  接続: tmux attach -t $session  (Ctrl-b d でデタッチ=BG継続)"
    log_info "  状態: メニュー項15 (セッション状態監視) で稼働確認"
    log_info "  停止: tmux kill-session -t $session"
    log_info "  ログ: $log_file"
  fi
}

# 直接実行時: setsid から呼ばれる watcher サブコマンドのみ受け付ける
# (source 時は BASH_SOURCE[0]!=$0 のため何もしない)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    __watch) shift; tmux__report_watcher "$@" ;;
    *)       : ;;
  esac
fi
