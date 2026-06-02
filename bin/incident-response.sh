#!/usr/bin/env bash
# ============================================================
# incident-response.sh — インシデント対応 (メニュー項I)
# 移植元: scripts/main/Start-IncidentResponse.ps1
#   P1/P2/P3 トリアージ → state.maintenance.open_incidents に記録 + 対応チェーン案内
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

STATE="${CCSU_STATE_FILE:-$CCSU_ROOT/state.json}"

main() {
  local prio=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --priority) prio="$2"; shift 2 ;;
      *) log_error "不明な引数: $1"; exit 1 ;;
    esac
  done
  [[ -z "$prio" ]] && read -rp "  優先度 (P1/P2/P3): " prio
  prio="${prio^^}"
  [[ "$prio" =~ ^P[123]$ ]] || { log_error "P1 / P2 / P3 のいずれかを指定してください"; exit 1; }

  local id now
  id="inc-$(date +%Y%m%d-%H%M%S)"
  now="$(date -Iseconds)"
  json_set "$STATE" \
    '.maintenance.open_incidents = ((.maintenance.open_incidents // []) + [{id:$id, priority:$p, opened_at:$t}]) | .maintenance.last_incident_id = $id | .maintenance.incident_count_30d = ((.maintenance.incident_count_30d // 0) + 1)' \
    --arg id "$id" --arg p "$prio" --arg t "$now"
  log_ok "インシデント記録: $id ($prio)"

  case "$prio" in
    P1) log_warn "P1 即時対応: Debugger → Developer → QA → DevOps → CTO (最終承認)" ;;
    P2) log_info "P2 当日〜翌日: Developer → Reviewer → QA → DevOps" ;;
    P3) log_info "P3 Backlog 登録 → 次週 Weekly DevOps で対応" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
