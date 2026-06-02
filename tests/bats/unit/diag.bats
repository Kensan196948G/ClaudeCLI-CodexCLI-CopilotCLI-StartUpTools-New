#!/usr/bin/env bats
# ============================================================
# diag.bats — libexec/*.sh 診断ラッパのテスト (メニュー項5-15)
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export CLAUDEOS_HOME="$TEST_TEMP/claudeos"
  mkdir -p "$CLAUDEOS_HOME/logs" "$CLAUDEOS_HOME/sessions"
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  cat > "$AI_STARTUP_CONFIG_PATH" <<JSON
{ "linuxBase": "$TEST_TEMP/projects", "projectsDir": "$TEST_TEMP/projects" }
JSON
  mkdir -p "$TEST_TEMP/projects/Alpha"
  export CCSU_STATE_FILE="$TEST_TEMP/state.json"
  echo '{ "agent_teams_usage": { "current_session": { "team_create_count": 2, "send_message_count": 5 } } }' > "$CCSU_STATE_FILE"
  LX="$REPO_ROOT/libexec"
}
teardown() { _bats_common_teardown; }

@test "diag-all-tools: exit 0 + 見出し" {
  run bash "$LX/diag-all-tools.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ツール確認"* ]]
}

@test "diag-mounts: exit 0 + 見出し" {
  run bash "$LX/diag-mounts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"疎通診断"* ]]
}

@test "setup-terminal: exit 0 + tmux 言及" {
  run bash "$LX/setup-terminal.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tmux"* ]]
}

@test "diag-mcp-health: exit 0" {
  run bash "$LX/diag-mcp-health.sh"
  [ "$status" -eq 0 ]
}

@test "diag-agent-teams: state の count を表示" {
  run bash "$LX/diag-agent-teams.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TeamCreate=2"* ]]
}

@test "diag-worktree: exit 0" {
  run bash "$LX/diag-worktree.sh"
  [ "$status" -eq 0 ]
}

@test "diag-architecture: exit 0 + 見出し" {
  run bash "$LX/diag-architecture.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Architecture Check"* ]]
}

@test "watch-claude-log --once: 最新ログを表示" {
  echo "TEST_LOG_LINE_42" > "$CLAUDEOS_HOME/logs/cron-test.log"
  run bash "$LX/watch-claude-log.sh" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_LOG_LINE_42"* ]]
}

@test "watch-claude-log --once: ログなしでも exit 0" {
  run bash "$LX/watch-claude-log.sh" --once
  [ "$status" -eq 0 ]
}

@test "watch-session --once: セッションを表示" {
  echo '{ "project": "Alpha", "status": "running", "start_time": "2026-06-01T10:00:00" }' > "$CLAUDEOS_HOME/sessions/s1.json"
  run bash "$LX/watch-session.sh" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"Alpha"* ]]
}
