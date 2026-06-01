#!/usr/bin/env bash
# ============================================================
# watch-session.sh — セッション状態監視 (メニュー項15)
# 移植元: scripts/tools/Watch-SessionInfoSSH.ps1 (SSH → ローカル読取)
#
# 構成 (改善): ①実行中の tmux セッション + 接続/停止の操作案内
#              ②最近のセッション履歴 (最新15件)
#   --once: 1回表示 (bats用) / 既定: 2秒ごとに更新 (Ctrl-C で戻る)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

_render_sessions() {
  local sdir="$1"

  # ① 実行中の tmux セッション (BG実行/cron実行の確認手段)
  if has_cmd tmux; then
    printf '  %s● 実行中の ClaudeOS セッション (tmux):%s\n' "$C_GREEN" "$C_RESET"
    local running; running="$(tmux ls 2>/dev/null | grep '^claudeos-' || true)"
    if [[ -n "$running" ]]; then
      printf '%s\n' "$running" | sed 's/^/      /'
      printf '      %s接続:%s tmux attach -t <名前>   (%sCtrl-b d%s でデタッチ=継続)\n' "$C_CYAN" "$C_RESET" "$C_YELLOW" "$C_RESET"
      printf '      %s停止:%s tmux kill-session -t <名前>\n' "$C_CYAN" "$C_RESET"
    else
      printf '      (実行中なし)\n'
    fi
  fi
  printf '\n'

  # ② 最近のセッション履歴 (最新15件)
  printf '  %s最近のセッション履歴 (最新15件):%s\n' "$C_CYAN" "$C_RESET"
  local f n=0
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
    printf '      %-30s %-10s %s\n' \
      "$(json_get "$f" '.project' '?')" \
      "$(json_get "$f" '.status' '?')" \
      "$(json_get "$f" '.start_time' '?')"
  done < <(ls -t "$sdir"/*.json 2>/dev/null | head -15)
  (( n == 0 )) && printf '      (記録なし)\n'
}

main() {
  local once=0; [[ "${1:-}" == "--once" ]] && once=1
  local sdir="${CCSU_SESSIONS_DIR:-$CCSU_HOME/sessions}"
  [[ -d "$sdir" ]] || { log_warn "セッションディレクトリがありません: $sdir"; return 0; }

  if (( once )); then
    log_info "セッション状態"
    _render_sessions "$sdir"
  else
    log_info "セッション状態監視 (Ctrl-C で戻る)"
    while true; do
      clear 2>/dev/null || true
      log_info "セッション状態 ($(date +%H:%M:%S))"
      _render_sessions "$sdir"
      sleep 2
    done
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
