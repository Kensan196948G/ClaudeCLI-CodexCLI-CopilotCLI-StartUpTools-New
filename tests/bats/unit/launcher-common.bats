#!/usr/bin/env bats
# ============================================================
# launcher-common.bats — lib/launcher-common.sh のユニットテスト
# 移植元: LauncherCommon.psm1 のローカル部分 (SMB/SSH は廃止)
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  cat > "$AI_STARTUP_CONFIG_PATH" <<JSON
{ "linuxBase": "$TEST_TEMP/projects", "projectsDir": "$TEST_TEMP/projects" }
JSON
  mkdir -p "$TEST_TEMP/projects/Alpha" "$TEST_TEMP/projects/Beta"
  touch "$TEST_TEMP/projects/.hidden"
  source "$REPO_ROOT/lib/launcher-common.sh"
}
teardown() { _bats_common_teardown; }

@test "launcher__project_list: プロジェクトを列挙" {
  run launcher__project_list
  [[ "$output" == *"Alpha"* ]]
  [[ "$output" == *"Beta"* ]]
}

@test "launcher__project_list: 隠しエントリを除外" {
  run launcher__project_list
  [[ "$output" != *".hidden"* ]]
}

@test "launcher__project_dir: 絶対パスを返す" {
  run launcher__project_dir Alpha
  [ "$output" = "$TEST_TEMP/projects/Alpha" ]
}

@test "launcher__project_exists: 存在すれば 0" {
  run launcher__project_exists Alpha
  [ "$status" -eq 0 ]
}

@test "launcher__project_exists: 不在なら非0" {
  run launcher__project_exists NoSuch
  [ "$status" -ne 0 ]
}

@test "launcher__select_project: 番号1でソート先頭(Alpha)を選択" {
  run bash -c "source '$REPO_ROOT/lib/launcher-common.sh'; printf '1\n' | launcher__select_project 2>/dev/null"
  [ "$output" = "Alpha" ]
}

@test "launcher__select_project: 範囲外番号は空" {
  run bash -c "source '$REPO_ROOT/lib/launcher-common.sh'; printf '99\n' | launcher__select_project 2>/dev/null"
  [ "$output" = "" ]
}
