#!/usr/bin/env bash
# ============================================================
# diag-architecture.sh — Architecture Check (メニュー項11)
# 移植元: scripts/test/Test-ArchitectureCheck.ps1
#   必須ファイルの存在と JSON 妥当性を確認
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

main() {
  log_info "Architecture Check"
  local root="${CCSU_ARCH_ROOT:-$CCSU_ROOT}"
  printf '\n  %s-- 必須ファイル --%s\n' "$C_CYAN" "$C_RESET"
  local f
  for f in CLAUDE.md README.md .mcp.json; do
    if [[ -f "$root/$f" ]]; then log_ok "$f"; else log_warn "$f なし"; fi
  done
  # config.json は実行時生成 (.gitignore)。template があれば OK 扱い
  if [[ -f "$root/config/config.json" ]]; then log_ok "config/config.json"
  elif [[ -f "$root/config/config.json.template" ]]; then log_info "config/config.json (未生成・template あり)"
  else log_warn "config/config.json なし"; fi

  printf '\n  %s-- JSON 妥当性 --%s\n' "$C_CYAN" "$C_RESET"
  for f in config/config.json state.json; do
    if [[ -f "$root/$f" ]]; then
      if json_valid "$root/$f"; then log_ok "$f は妥当"; else log_error "$f は不正な JSON"; fi
    fi
  done
  printf '\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
