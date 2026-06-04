#!/usr/bin/env bats
# ============================================================
# bin-ops.bats — state操作系 bin のテスト
#   deploy-prep / maintenance-mode / weekly-devops / incident-response /
#   dashboard-service / set-statusline
# systemctl/loginctl/crontab は PATH スタブ化 (実環境を汚さない)
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export CCSU_STATE_FILE="$TEST_TEMP/state.json"
  cat > "$CCSU_STATE_FILE" <<'JSON'
{ "deploy": { "ready": false }, "project": {}, "maintenance": { "phase_mode": "development", "sla_target_availability": 0.995, "mttr_target_hours": 4, "error_budget_remaining_pct": 100, "incident_count_30d": 0 } }
JSON
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  echo '{ "projects": "/tmp", "projectsDir": "/tmp" }' > "$AI_STARTUP_CONFIG_PATH"
  # 実環境を汚さないスタブ群
  make_stub_bin systemctl 'exit 0'
  make_stub_bin loginctl 'exit 0'
  export CRON_STORE="$TEST_TEMP/cron.store"
  make_stub_bin crontab '
store="${CRON_STORE:?}"
case "${1:-}" in
  -l) [[ -f "$store" ]] && cat "$store" || exit 1 ;;
  -)  cat > "$store" ;;
  *)  exit 2 ;;
esac
'
  export CCSU_SYSTEMD_UNIT_PATH="$TEST_TEMP/claudeos-dashboard.service"
  export CCSU_CLAUDE_SETTINGS="$TEST_TEMP/claude-settings.json"
  B="$REPO_ROOT/bin"
}
teardown() { _bats_common_teardown; }

@test "deploy-prep: state.deploy.ready=true / environment" {
  run bash "$B/deploy-prep.sh" --env staging
  [ "$status" -eq 0 ]
  [ "$(jq -r '.deploy.ready' "$CCSU_STATE_FILE")" = "true" ]
  [ "$(jq -r '.deploy.environment' "$CCSU_STATE_FILE")" = "staging" ]
}

@test "deploy-prep: 不正な env でエラー" {
  run bash "$B/deploy-prep.sh" --env bogus
  [ "$status" -ne 0 ]
}

@test "maintenance-mode --yes: phase_mode=maintenance" {
  run bash "$B/maintenance-mode.sh" --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r '.maintenance.phase_mode' "$CCSU_STATE_FILE")" = "maintenance" ]
  [ "$(jq -r '.project.phase_mode' "$CCSU_STATE_FILE")" = "maintenance" ]
}

@test "weekly-devops: KPI を表示" {
  run bash "$B/weekly-devops.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SLA"* ]]
  [[ "$output" == *"MTTR"* ]]
}

@test "incident-response --priority P1: open_incidents に記録" {
  run bash "$B/incident-response.sh" --priority P1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.maintenance.open_incidents | length' "$CCSU_STATE_FILE")" -ge 1 ]
  [ "$(jq -r '.maintenance.incident_count_30d' "$CCSU_STATE_FILE")" -eq 1 ]
}

@test "incident-response: 不正な優先度でエラー" {
  run bash "$B/incident-response.sh" --priority P9
  [ "$status" -ne 0 ]
}

@test "dashboard-service --register: systemd unit を生成 (スタブ)" {
  run bash "$B/dashboard-service.sh" --register --run-now
  [ "$status" -eq 0 ]
  [ -f "$CCSU_SYSTEMD_UNIT_PATH" ]
  grep -q 'serve-dashboard.js' "$CCSU_SYSTEMD_UNIT_PATH"
}

@test "dashboard-service --unregister: unit を削除" {
  bash "$B/dashboard-service.sh" --register --run-now
  run bash "$B/dashboard-service.sh" --unregister
  [ "$status" -eq 0 ]
  [ ! -f "$CCSU_SYSTEMD_UNIT_PATH" ]
}

@test "set-statusline: settings.json に statusLine を設定" {
  run bash "$B/set-statusline.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.type' "$CCSU_CLAUDE_SETTINGS")" = "command" ]
}
