#!/usr/bin/env bash
# ============================================================
# diag-mounts.sh — マウント / ネットワーク疎通診断 (メニュー項6)
# 移植元: scripts/test/test-drive-mapping.ps1 を Linux 向けに転用
#   (Windows のドライブマッピング診断 → df/プロジェクトdir/ping)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"

main() {
  log_info "マウント / ネットワーク疎通診断"
  printf '\n  %s-- ディスク使用量 (HOME) --%s\n' "$C_CYAN" "$C_RESET"
  df -h "$HOME" 2>/dev/null || log_warn "df 失敗"

  printf '\n  %s-- プロジェクトディレクトリ --%s\n' "$C_CYAN" "$C_RESET"
  local base; base="$(config_projects_dir)"
  if [[ -d "$base" ]]; then
    local n; n="$(ls -1 "$base" 2>/dev/null | grep -vc '^\.' || echo 0)"
    log_ok "$base (${n} プロジェクト)"
  else
    log_warn "存在しません: $base"
  fi

  printf '\n  %s-- ネットワーク疎通 --%s\n' "$C_CYAN" "$C_RESET"
  if command -v ping >/dev/null 2>&1; then
    if ping -c1 -W2 github.com >/dev/null 2>&1; then log_ok "github.com 到達"; else log_warn "github.com 到達不可"; fi
  else
    log_warn "ping 未検出"
  fi
  printf '\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
