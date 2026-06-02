#!/usr/bin/env bats
# ============================================================
# json.bats — lib/json.sh のユニットテスト
# 移植元: 各 .psm1 の ConvertFrom-Json/ConvertTo-Json の挙動
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  source "$REPO_ROOT/lib/json.sh"
}
teardown() { _bats_common_teardown; }

# --- json_get ---

@test "json_get: ネストしたスカラ値を取得" {
  echo '{"a":{"b":"hello"}}' > "$TEST_TEMP/t.json"
  run json_get "$TEST_TEMP/t.json" '.a.b'
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "json_get: 不在キーで default を返す" {
  echo '{"a":1}' > "$TEST_TEMP/t.json"
  run json_get "$TEST_TEMP/t.json" '.missing' 'DEF'
  [ "$output" = "DEF" ]
}

@test "json_get: ファイル不在で default を返す" {
  run json_get "$TEST_TEMP/nope.json" '.x' 'fallback'
  [ "$output" = "fallback" ]
}

@test "json_get: null 値で default を返す" {
  echo '{"a":null}' > "$TEST_TEMP/t.json"
  run json_get "$TEST_TEMP/t.json" '.a' 'DEF'
  [ "$output" = "DEF" ]
}

@test "json_get: default 省略時は空文字" {
  echo '{"a":1}' > "$TEST_TEMP/t.json"
  run json_get "$TEST_TEMP/t.json" '.missing'
  [ "$output" = "" ]
}

# --- json_get_raw ---

@test "json_get_raw: 配列を compact JSON で取得" {
  echo '{"arr":[1,2,3]}' > "$TEST_TEMP/t.json"
  run json_get_raw "$TEST_TEMP/t.json" '.arr'
  [ "$output" = "[1,2,3]" ]
}

# --- json_set ---

@test "json_set: 既存ファイルの数値を更新 (atomic)" {
  echo '{"x":1}' > "$TEST_TEMP/s.json"
  run json_set "$TEST_TEMP/s.json" '.x = ($v|tonumber)' --arg v 42
  [ "$status" -eq 0 ]
  run json_get "$TEST_TEMP/s.json" '.x'
  [ "$output" = "42" ]
}

@test "json_set: 文字列値を設定" {
  echo '{}' > "$TEST_TEMP/s.json"
  json_set "$TEST_TEMP/s.json" '.phase = $v' --arg v 'Build'
  run json_get "$TEST_TEMP/s.json" '.phase'
  [ "$output" = "Build" ]
}

@test "json_set: ファイル不在時は新規生成" {
  json_set "$TEST_TEMP/new.json" '{created: $v}' --arg v 'yes'
  [ -f "$TEST_TEMP/new.json" ]
  run json_get "$TEST_TEMP/new.json" '.created'
  [ "$output" = "yes" ]
}

@test "json_set: 書き込み後も妥当な JSON を保つ" {
  echo '{"a":1}' > "$TEST_TEMP/s.json"
  json_set "$TEST_TEMP/s.json" '.b = 2'
  run json_valid "$TEST_TEMP/s.json"
  [ "$status" -eq 0 ]
}

@test "json_set: .tmp 一時ファイルを残さない" {
  echo '{"a":1}' > "$TEST_TEMP/s.json"
  json_set "$TEST_TEMP/s.json" '.a = 2'
  run bash -c "ls $TEST_TEMP/*.tmp 2>/dev/null | wc -l"
  [ "$output" -eq 0 ]
}

# --- json_valid ---

@test "json_valid: 妥当な JSON で成功" {
  echo '{"ok":true}' > "$TEST_TEMP/v.json"
  run json_valid "$TEST_TEMP/v.json"
  [ "$status" -eq 0 ]
}

@test "json_valid: 不正な JSON を検出" {
  echo 'not json{' > "$TEST_TEMP/bad.json"
  run json_valid "$TEST_TEMP/bad.json"
  [ "$status" -ne 0 ]
}

# --- json_append_line ---

@test "json_append_line: JSONL を順次追記" {
  json_append_line "$TEST_TEMP/log.jsonl" '{"e":1}'
  json_append_line "$TEST_TEMP/log.jsonl" '{"e":2}'
  run bash -c "wc -l < $TEST_TEMP/log.jsonl"
  [ "$output" -eq 2 ]
}

# --- json_expand_path ---

@test "json_expand_path: USERPROFILE とバックスラッシュを Linux 化" {
  run json_expand_path '%USERPROFILE%\.ai-startup\recent.json'
  [ "$output" = "$HOME/.ai-startup/recent.json" ]
}

@test "json_expand_path: 通常の Linux パスはそのまま" {
  run json_expand_path '/home/kensan/x.json'
  [ "$output" = "/home/kensan/x.json" ]
}
