#!/usr/bin/env bats
# ============================================================
# start-dashboard.bats — bin/start-dashboard.sh のテスト
# node を PATH スタブ化。実稼働ポートを避け未使用ポートで検証。
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  make_stub_bin node 'echo "node $*"; exit 0'
  make_stub_bin xdg-open 'exit 0'
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  echo '{ "projects": "/tmp", "projectsDir": "/tmp" }' > "$AI_STARTUP_CONFIG_PATH"
  SCRIPT="$REPO_ROOT/bin/start-dashboard.sh"
  TPORT=39917   # テスト専用の未使用ポート (3737 等の実稼働を避ける)
}
teardown() { _bats_common_teardown; }

@test "start-dashboard: 空きポートで serve-dashboard.js を node 起動" {
  run bash "$SCRIPT" --no-browser --port "$TPORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"serve-dashboard.js"* ]]
  [[ "$output" == *"$TPORT"* ]]
}

@test "start-dashboard: Windows用 URL (/mission-control) を案内" {
  run bash "$SCRIPT" --no-browser --port "$TPORT"
  [[ "$output" == *"/mission-control"* ]]
}

@test "start-dashboard: 不明な引数でエラー" {
  run bash "$SCRIPT" --frobnicate
  [ "$status" -ne 0 ]
}
