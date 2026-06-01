#!/usr/bin/env bash
# ============================================================
# watch-session.sh — セッション状態監視 / 操作 (メニュー項15)
# 移植元: scripts/tools/Watch-SessionInfoSSH.ps1 (SSH → ローカル読取)
#
# 対話モード (既定): 実行中 claudeos-* セッションを番号付きで列挙し、
#   番号選択 → [a]接続(attach) / [s]停止(kill) を選べる。複数セッション対応。
# --once: 非対話の1回表示 (bats用)。
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

TMUX_BIN="${CCSU_TMUX_BIN:-tmux}"

# 実行中の claudeos-* セッション名 (1行1名)
_running_sessions() {
  "$TMUX_BIN" ls 2>/dev/null | grep '^claudeos-' | cut -d: -f1 || true
}

# 最近のセッション履歴 (最新15件)
_render_history() {
  local sdir="$1" f n=0
  printf '  %s最近のセッション履歴 (最新15件):%s\n' "$C_CYAN" "$C_RESET"
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
    printf '      %-30s %-10s %s\n' \
      "$(json_get "$f" '.project' '?')" \
      "$(json_get "$f" '.status' '?')" \
      "$(json_get "$f" '.start_time' '?')"
  done < <(ls -t "$sdir"/*.json 2>/dev/null | head -15)
  if (( n == 0 )); then printf '      (記録なし)\n'; fi
  return 0
}

# 非対話表示 (--once / bats)
_render_once() {
  local sdir="$1"
  if has_cmd "$TMUX_BIN"; then
    printf '  %s● 実行中の ClaudeOS セッション (tmux):%s\n' "$C_GREEN" "$C_RESET"
    local r; r="$(_running_sessions)"
    if [[ -n "$r" ]]; then printf '%s\n' "$r" | sed 's/^/      /'; else printf '      (実行中なし)\n'; fi
  fi
  printf '\n'
  _render_history "$sdir"
}

# セッション操作: [a]接続 / [s]停止 / [c]キャンセル
_session_action() {
  local s="$1" safe="${1#claudeos-}"
  printf '\n  選択: %s%s%s\n' "$C_GREEN" "$s" "$C_RESET"
  printf '    %s[a]%s 接続(attach)   %s[s]%s 停止(kill)   %s[c]%s キャンセル\n' \
    "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$C_RESET" "$C_GRAY" "$C_RESET"
  local op; read -rp "  操作: " op
  case "${op,,}" in
    a) log_info "接続します... (Ctrl-b d でデタッチ=BG継続)"; sleep 1
       "$TMUX_BIN" attach -t "$s" || true ;;
    s) if "$TMUX_BIN" kill-session -t "$s" 2>/dev/null; then log_ok "停止しました: $s"; else log_warn "停止失敗 (既に終了?): $s"; fi
       "$TMUX_BIN" kill-session -t "_keeper_$safe" 2>/dev/null || true
       sleep 1 ;;
    *) : ;;
  esac
}

# 対話メニュー: 番号選択 → 接続/停止
_interactive_menu() {
  local sdir="$1"
  while true; do
    clear 2>/dev/null || true
    log_info "セッション状態監視 ($(date +%H:%M:%S))"

    local -a sess; mapfile -t sess < <(_running_sessions)
    printf '\n  %s● 実行中の ClaudeOS セッション:%s\n' "$C_GREEN" "$C_RESET"
    if (( ${#sess[@]} == 0 )); then
      printf '      (実行中なし)\n'
    else
      local i info
      for i in "${!sess[@]}"; do
        info="$("$TMUX_BIN" ls 2>/dev/null | grep "^${sess[$i]}:" | head -1 || true)"
        printf '      %s[%d]%s %s\n' "$C_YELLOW" "$((i + 1))" "$C_RESET" "${info:-${sess[$i]}}"
      done
    fi
    printf '\n'
    _render_history "$sdir"

    printf '\n  %s操作:%s 番号=選択(接続/停止)   r=再表示   0=戻る\n' "$C_CYAN" "$C_RESET"
    local choice; read -rp "  入力: " choice
    case "$choice" in
      0) return 0 ;;
      r|R|"") continue ;;
      *[!0-9]*) log_warn "無効な入力です"; sleep 1 ;;
      *) if (( choice >= 1 && choice <= ${#sess[@]} )); then
           _session_action "${sess[$((choice - 1))]}"
         else
           log_warn "範囲外の番号です: $choice"; sleep 1
         fi ;;
    esac
  done
}

main() {
  local once=0; [[ "${1:-}" == "--once" ]] && once=1
  local sdir="${CCSU_SESSIONS_DIR:-$CCSU_HOME/sessions}"
  [[ -d "$sdir" ]] || { log_warn "セッションディレクトリがありません: $sdir"; return 0; }
  if (( once )); then
    _render_once "$sdir"
  else
    _interactive_menu "$sdir"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
