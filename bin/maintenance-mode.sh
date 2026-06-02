#!/usr/bin/env bash
# ============================================================
# maintenance-mode.sh — 保守モードへ移行 (メニュー項M)
# 移植元: scripts/main/Start-MaintenanceMode.ps1
#   state.maintenance.phase_mode=maintenance / project.phase_mode=maintenance / released_at
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

STATE="${CCSU_STATE_FILE:-$CCSU_ROOT/state.json}"

main() {
  local yes=0
  [[ "${1:-}" == "--yes" ]] && yes=1

  if (( yes == 0 )); then
    local c; read -rp "  保守モードへ移行します。デプロイ完了を確認済みですか？ (y/N): " c
    [[ "${c^^}" == "Y" ]] || { log_info "キャンセルしました"; return 0; }
  fi

  local now; now="$(date -Iseconds)"
  json_set "$STATE" \
    '.maintenance.phase_mode = "maintenance" | .project.phase_mode = "maintenance" | .maintenance.released_at = $t' \
    --arg t "$now"
  log_ok "保守モードへ移行: phase_mode=maintenance / released_at=$now"
  log_info "以降は maintenance-loop (Monitor→Triage→Fix→Verify→Deploy) で運用されます"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
