#!/usr/bin/env bats
# ============================================================
# notify.bats — lib/notify.sh のユニットテスト
# ffplay を PATH スタブ化 (呼ばれたら $PLAY_MARKER を作成)
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  touch "$TEST_TEMP/alert.mp3"
  cat > "$AI_STARTUP_CONFIG_PATH" <<JSON
{ "notifications": { "soundEnabled": true, "sounds": { "claude": "$TEST_TEMP/alert.mp3" } } }
JSON
  export PLAY_MARKER="$TEST_TEMP/played"
  make_stub_bin ffplay 'touch "$PLAY_MARKER"; exit 0'
  source "$REPO_ROOT/lib/notify.sh"
}
teardown() { _bats_common_teardown; }

@test "notify__play: 有効時に ffplay を呼ぶ" {
  notify__play claude --wait
  [ -f "$PLAY_MARKER" ]
}

@test "notify__play: CLAUDEOS_SOUND_ENABLED=0 で鳴らさない" {
  CLAUDEOS_SOUND_ENABLED=0 notify__play claude --wait
  [ ! -f "$PLAY_MARKER" ]
}

@test "notify__play: soundEnabled=false で鳴らさない" {
  echo '{ "notifications": { "soundEnabled": false } }' > "$AI_STARTUP_CONFIG_PATH"
  notify__play claude --wait
  [ ! -f "$PLAY_MARKER" ]
}

@test "notify__play: 音声ファイル不在で鳴らさない" {
  rm -f "$TEST_TEMP/alert.mp3"
  notify__play claude --wait
  [ ! -f "$PLAY_MARKER" ]
}

@test "notify__play: 未定義 tool で鳴らさない" {
  notify__play unknowntool --wait
  [ ! -f "$PLAY_MARKER" ]
}

@test "notify__bell: 正常終了" {
  run notify__bell
  [ "$status" -eq 0 ]
}
