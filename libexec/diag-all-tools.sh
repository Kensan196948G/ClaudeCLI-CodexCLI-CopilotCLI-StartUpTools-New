#!/usr/bin/env bash
# ============================================================
# diag-all-tools.sh — ツール確認・診断 (メニュー項5)
# 移植元: scripts/test/Test-AllTools.ps1 (Linux 向けツール集合に調整)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

main() {
  log_info "ツール確認・診断"
  printf '\n'
  local t path
  for t in claude codex copilot git gh node npm jq tmux python3 ffplay shellcheck bats crontab; do
    if has_cmd "$t"; then
      path="$(command -v "$t")"
      printf '  %s✓%s %-11s %s\n' "$C_GREEN" "$C_RESET" "$t" "$path"
    else
      printf '  %s✗%s %-11s %s(未検出)%s\n' "$C_RED" "$C_RESET" "$t" "$C_GRAY" "$C_RESET"
    fi
  done
  printf '\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
