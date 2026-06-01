#!/usr/bin/env bash
# ============================================================
# watch-claude-log.sh — Claude ログ監視 (メニュー項13)
# 移植元: scripts/tools/Watch-ClaudeLog.ps1
#   ~/.claudeos/logs の最新ログを tail (cron/手動 tmux 両方のログ)
#   --once: 直近20行を1回表示 (bats用) / 既定: tail -f (Ctrl-C で戻る)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

main() {
  local once=0; [[ "${1:-}" == "--once" ]] && once=1
  local logs_dir="${CCSU_LOGS_DIR:-$CCSU_HOME/logs}"
  [[ -d "$logs_dir" ]] || { log_warn "ログディレクトリがありません: $logs_dir"; return 0; }
  local latest; latest="$(ls -t "$logs_dir"/*.log 2>/dev/null | head -1 || true)"
  [[ -n "$latest" ]] || { log_warn "ログファイルがありません: $logs_dir"; return 0; }

  log_info "最新ログ: $latest"
  if (( once )); then
    tail -n 20 "$latest" 2>/dev/null || true
  else
    log_info "(Ctrl-C で戻る)"
    tail -n 30 -f "$latest"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
