#!/usr/bin/env bats
# ============================================================
# start-dashboard.bats — bin/start-dashboard.sh のテスト
# node を PATH スタブ化 (serve-dashboard.js を即終了させる)
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  make_stub_bin node 'echo "node $*"; exit 0'
  make_stub_bin xdg-open 'exit 0'
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  echo '{ "linuxBase": "/tmp", "projectsDir": "/tmp" }' > "$AI_STARTUP_CONFIG_PATH"
  # serve-dashboard.js の存在は REPO_ROOT 実体を使う (保持ファイル)
  SCRIPT="$REPO_ROOT/bin/start-dashboard.sh"
}
teardown() { _bats_common_teardown; }

@test "start-dashboard: serve-dashboard.js を node 起動 (--no-browser)" {
  run bash "$SCRIPT" --no-browser
  [ "$status" -eq 0 ]
  [[ "$output" == *"serve-dashboard.js"* ]]
}

@test "start-dashboard: 既定ポート 3737" {
  run bash "$SCRIPT" --no-browser
  [[ "$output" == *"3737"* ]]
}

@test "start-dashboard: --port で上書き" {
  run bash "$SCRIPT" --no-browser --port 4000
  [[ "$output" == *"4000"* ]]
}

@test "start-dashboard: 不明な引数でエラー" {
  run bash "$SCRIPT" --frobnicate
  [ "$status" -ne 0 ]
}
