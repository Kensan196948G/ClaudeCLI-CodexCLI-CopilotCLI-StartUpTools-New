#!/usr/bin/env bash
# ============================================================
# start-claude.sh — ClaudeCode 起動エントリ (Linux native)
#
# 移植元: scripts/main/Start-ClaudeCode.ps1 の「ローカル分岐のみ」
#   廃止: SSH デプロイ / base64 配布 / PTY bridge (約400行) → ローカル実行に一本化
#   多重起動防止: Named Mutex → tmux has-session (tmux_run 内)
#
# 使い方 (menu.sh から):
#   start-claude.sh --project P --foreground [--duration 300]   # L1: tmux attach
#   start-claude.sh --project P --background [--duration 300]   # S1: detached
#   --local は互換用 (ローカル一本化のため常にローカル)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"
# shellcheck source=lib/launcher-common.sh
source "$SCRIPT_DIR/../lib/launcher-common.sh"
# shellcheck source=lib/tmux-runner.sh
source "$SCRIPT_DIR/../lib/tmux-runner.sh"
# shellcheck source=lib/notify.sh
source "$SCRIPT_DIR/../lib/notify.sh"

main() {
  local project="" mode="foreground" duration=300
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)    project="$2"; shift 2 ;;
      --foreground) mode="foreground"; shift ;;
      --background) mode="background"; shift ;;
      --duration)   duration="$2"; shift 2 ;;
      --local)      shift ;;   # 互換: ローカル一本化のため無視
      *) log_error "不明な引数: $1"; exit 1 ;;
    esac
  done

  require_cmd claude "npm i -g @anthropic-ai/claude-code"

  # メール送信用に ~/.env-claudeos を読み込む (SMTP creds / CLAUDEOS_EMAIL_ENABLED)。
  # cron-launcher.sh と同様。set -a で sourced 変数を確実に export し、
  # tmux_run が起動する終了レポート watcher (setsid 子プロセス) へ継承させる。
  # テストは CCSU_SKIP_ENV_FILE=1 でスキップ。
  if [[ "${CCSU_SKIP_ENV_FILE:-0}" != "1" && -f "$HOME/.env-claudeos" ]]; then
    # shellcheck disable=SC1091
    set -a; source "$HOME/.env-claudeos"; set +a
  fi

  [[ -z "$project" ]] && project="$(launcher__select_project)"
  [[ -n "$project" ]] || { log_error "プロジェクトが選択されていません"; exit 1; }
  launcher__project_exists "$project" || { log_error "プロジェクトが存在しません: $(launcher__project_dir "$project")"; exit 1; }

  notify__play claude   # 起動通知音 (非ブロッキング・失敗無害)

  local safe session
  safe="$(ccsu_safe_name "$project")"
  session="claudeos-$safe"

  # supervisor state ファイル: start 前の mtime を baseline として記録する。
  # start 後に mtime が前進する (= supervisor が今回 state を書き換えた) のを
  # 待ってから status を読むことで、前回 run の stale な blocked/stopped/goal-reached
  # を誤検出しないようにする (ファイル存在チェックだけでは古い状態を拾う)。
  local _sup_state="$HOME/.claudeos/supervisor/${safe}.json"
  local _sup_mtime_before
  _sup_mtime_before="$(stat -c %Y "$_sup_state" 2>/dev/null || echo 0)"

  # supervisor 経由で起動 (--force: cron 競合があっても手動起動を優先)
  bash "$SCRIPT_DIR/autonomy.sh" start "$project" --duration "$duration" --force || {
    log_error "supervisor 起動に失敗しました: $project"; exit 1
  }

  # supervisor が今回の起動で state を更新する (mtime 前進) のを最大 ~3 秒待機。
  # mtime が動かないまま timeout した場合は従来どおり現状の state を読む。
  local _w _sup_mtime_now
  for ((_w = 0; _w < 15; _w++)); do
    _sup_mtime_now="$(stat -c %Y "$_sup_state" 2>/dev/null || echo 0)"
    [[ "$_sup_mtime_now" -gt "$_sup_mtime_before" ]] && break
    sleep 0.2
  done

  # supervisor が即時停止した場合 (blocked/stopped/goal-reached) を検出し対処
  local _sup_status="" _sup_reason=""
  if [[ -f "$_sup_state" ]]; then
    _sup_status="$(jq -r '.status // ""' "$_sup_state" 2>/dev/null || true)"
    _sup_reason="$(jq -r '.last_reason // ""' "$_sup_state" 2>/dev/null || true)"
  fi

  if [[ "$_sup_status" =~ ^(blocked|stopped|goal-reached)$ ]]; then
    log_warn "supervisor 停止 (status=$_sup_status)"
    log_warn "  停止理由: $_sup_reason"

    # プロジェクトの blocked_issues をリスト表示
    local _pstate _blocked_list
    _pstate="$(config_projects_dir)/$project/state.json"
    if [[ -f "$_pstate" ]] && has_cmd jq; then
      _blocked_list="$(jq -r '.blocked_issues[]? // empty' "$_pstate" 2>/dev/null || true)"
      if [[ -n "$_blocked_list" ]]; then
        log_warn "  Blocked Issues:"
        while IFS= read -r _bi; do
          log_warn "    - $_bi"
        done <<< "$_blocked_list"
      fi
    fi

    printf "\n"
    log_info "  ※ supervisorは blocked_issues が存在する間、自律起動を行いません"
    log_info "  ※ Y で起動した場合: 自動再起動なし (手動起動モード)"

    if [[ "$mode" == "foreground" ]]; then
      local _ans
      printf "  直接起動しますか? (Y/N): "
      read -r _ans
      if [[ "${_ans^^}" == "Y" ]]; then
        log_info "手動モードで起動します (supervisor なし・自動再起動なし)"
        tmux_run "$project" "$duration" "$mode"
      else
        log_info "起動をキャンセルしました"
        log_info "  blocked_issues を解消すると supervisor 経由で正常起動できます"
      fi
    elif [[ "$mode" == "background" ]]; then
      local _ans
      printf "  直接起動しますか? (Y/N) [背景: 自動再起動なし]: "
      read -r _ans
      if [[ "${_ans^^}" == "Y" ]]; then
        log_info "手動モードで起動します (supervisor なし・自動再起動なし)"
        tmux_run "$project" "$duration" "$mode"
      else
        log_info "起動をキャンセルしました"
      fi
    fi
    return 0
  fi

  if [[ "$mode" == "foreground" ]]; then
    # tmux セッションが起動するまで最大30秒待機
    local i
    for ((i = 0; i < 60; i++)); do
      "$TMUX_BIN" has-session -t "$session" 2>/dev/null && break
      sleep 0.5
    done
    if "$TMUX_BIN" has-session -t "$session" 2>/dev/null; then
      log_info "セッションへ接続: $session"
      "$TMUX_BIN" attach-session -t "$session"
    else
      log_warn "tmux セッション起動待ちタイムアウト: $session"
      log_info "  確認: tmux ls  /  bash bin/autonomy.sh status $project"
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
