#!/usr/bin/env bash
# ============================================================
# watch-session.sh — セッション状態監視 (メニュー項15)
# 移植元: scripts/tools/Watch-SessionInfoSSH.ps1 (SSH → ローカル読取)
#   ~/.claudeos/sessions/*.json + tmux claudeos-* を表示
#   --once: 1回表示 (bats用) / 既定: 2秒ごとに更新 (Ctrl-C で戻る)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

_render_sessions() {
  local sdir="$1" f proj status start found=0
  for f in "$sdir"/*.json; do
    [[ -f "$f" ]] || continue
    found=1
    proj="$(json_get "$f" '.project' '?')"
    status="$(json_get "$f" '.status' '?')"
    start="$(json_get "$f" '.start_time' '?')"
    printf '  %-28s %-10s %s\n' "$proj" "$status" "$start"
  done
  (( found == 0 )) && printf '  (セッション記録なし)\n'
  if has_cmd tmux; then
    printf '  %s-- tmux セッション --%s\n' "$C_CYAN" "$C_RESET"
    tmux ls 2>/dev/null | grep '^claudeos-' || printf '  (実行中なし)\n'
  fi
}

main() {
  local once=0; [[ "${1:-}" == "--once" ]] && once=1
  local sdir="${CCSU_SESSIONS_DIR:-$CCSU_HOME/sessions}"
  [[ -d "$sdir" ]] || { log_warn "セッションディレクトリがありません: $sdir"; return 0; }

  if (( once )); then
    log_info "セッション一覧:"
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
