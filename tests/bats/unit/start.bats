#!/usr/bin/env bats
# ============================================================
# start.bats — ルート start.sh が menu.sh へ委譲することを確認
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  echo '{ "projects": "/home/kensan/Projects", "projectsDir": "/home/kensan/Projects" }' > "$AI_STARTUP_CONFIG_PATH"
  export CCSU_STATE_FILE="$TEST_TEMP/state.json"
  echo '{}' > "$CCSU_STATE_FILE"
  export CLAUDEOS_PLAIN_OUTPUT=1
}
teardown() { _bats_common_teardown; }

@test "start.sh: menu.sh --render に委譲しメニューを描画" {
  run bash "$REPO_ROOT/start.sh" --render
  [ "$status" -eq 0 ]
  [[ "$output" == *"スタートアップツール"* ]]
  [[ "$output" == *"L1"* ]]
}
