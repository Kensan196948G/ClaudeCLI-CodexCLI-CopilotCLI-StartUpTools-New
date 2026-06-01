#!/usr/bin/env bash
# ============================================================
# diag-mcp-health.sh — MCP ヘルスチェック (メニュー項8)
# 移植元: scripts/test/Test-McpHealth.ps1 (.mcp.json の確認)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

main() {
  log_info "MCP ヘルスチェック"
  local mcp="${CCSU_MCP_FILE:-$CCSU_ROOT/.mcp.json}"
  if [[ -f "$mcp" ]] && json_valid "$mcp"; then
    log_ok ".mcp.json は妥当な JSON: $mcp"
    local servers; servers="$(jq -r '.mcpServers // {} | keys[]' "$mcp" 2>/dev/null || true)"
    if [[ -n "$servers" ]]; then
      printf '  %s登録サーバー:%s\n' "$C_CYAN" "$C_RESET"
      printf '%s\n' "$servers" | while read -r s; do printf '    - %s\n' "$s"; done
    else
      log_warn "mcpServers が空です"
    fi
  else
    log_warn ".mcp.json が見つからないか不正です: $mcp"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
