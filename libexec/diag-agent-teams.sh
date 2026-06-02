#!/usr/bin/env bash
# ============================================================
# diag-agent-teams.sh — Agent Teams ランタイム (メニュー項9)
# 移植元: scripts/test/Test-AgentTeams.ps1
#   state.json の agent_teams_usage を表示 + agent-teams-status.js (あれば)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

main() {
  log_info "Agent Teams ランタイム"
  local state="${CCSU_STATE_FILE:-$CCSU_ROOT/state.json}"
  if [[ -f "$state" ]]; then
    local tc sc
    tc="$(json_get "$state" '.agent_teams_usage.current_session.team_create_count' '0')"
    sc="$(json_get "$state" '.agent_teams_usage.current_session.send_message_count' '0')"
    log_ok "現セッション: TeamCreate=$tc / SendMessage=$sc"
    local js="$CCSU_ROOT/scripts/tools/agent-teams-status.js"
    if [[ -f "$js" ]] && has_cmd node; then
      printf '  %s-- agent-teams-status.js --%s\n' "$C_CYAN" "$C_RESET"
      ( cd "$CCSU_ROOT" && node "$js" 2>/dev/null ) || log_info "(agent-teams-status.js: 実行時データなし)"
    fi
  else
    log_info "state.json 未生成です (cron/手動の claude 実行で生成されます)"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
