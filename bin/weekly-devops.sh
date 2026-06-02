#!/usr/bin/env bash
# ============================================================
# weekly-devops.sh — 週次 DevOps レポート確認 (メニュー項W)
# 移植元: scripts/main/Start-WeeklyDevOps.ps1
#   state.maintenance の保守 KPI を表示 (SLA / MTTR / Error Budget / incidents)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

STATE="${CCSU_STATE_FILE:-$CCSU_ROOT/state.json}"

main() {
  log_info "週次 DevOps レポート"
  [[ -f "$STATE" ]] || { log_warn "state.json がありません: $STATE"; return 0; }
  printf '\n'
  printf '  %sSLA 目標稼働率   :%s %s\n' "$C_CYAN" "$C_RESET" "$(json_get "$STATE" '.maintenance.sla_target_availability' 'n/a')"
  printf '  %sMTTR 目標 (時間) :%s %s\n' "$C_CYAN" "$C_RESET" "$(json_get "$STATE" '.maintenance.mttr_target_hours' 'n/a')"
  printf '  %sError Budget 残%% :%s %s\n' "$C_CYAN" "$C_RESET" "$(json_get "$STATE" '.maintenance.error_budget_remaining_pct' 'n/a')"
  printf '  %s30日インシデント :%s %s\n' "$C_CYAN" "$C_RESET" "$(json_get "$STATE" '.maintenance.incident_count_30d' '0')"
  printf '  %s直近スキャン     :%s deps=%s / security=%s\n' "$C_CYAN" "$C_RESET" \
    "$(json_get "$STATE" '.maintenance.last_dependency_scan' '未実施')" \
    "$(json_get "$STATE" '.maintenance.last_security_audit' '未実施')"
  printf '\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
