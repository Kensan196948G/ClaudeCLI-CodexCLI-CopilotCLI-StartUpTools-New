#!/usr/bin/env bats
# ============================================================
# config.bats — lib/config-loader.sh のユニットテスト
# 移植元: tests/unit/Config.Tests.ps1 / ConfigSchema.Tests.ps1 の主旨
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  cat > "$AI_STARTUP_CONFIG_PATH" <<'JSON'
{
  "projectsDir": "D:\\",
  "linuxUser": "kensan",
  "projects": "/home/kensan/Projects",
  "tools": {
    "defaultTool": "claude",
    "claude": { "enabled": true, "command": "claude" },
    "codex": { "enabled": false, "command": "codex" }
  },
  "notifications": {
    "soundEnabled": true,
    "sounds": { "claude": "%USERPROFILE%\\alert.mp3" }
  },
  "recentProjects": { "historyFile": "%USERPROFILE%\\.ai-startup\\recent.json" }
}
JSON
  source "$REPO_ROOT/lib/config-loader.sh"
}
teardown() { _bats_common_teardown; }

@test "config_projects_dir: projects を優先 (Windows D:\\ ではなく)" {
  run config_projects_dir
  [ "$output" = "/home/kensan/Projects" ]
}

@test "config_linux_user: linuxUser を取得" {
  run config_linux_user
  [ "$output" = "kensan" ]
}

@test "config_default_tool: defaultTool を取得" {
  run config_default_tool
  [ "$output" = "claude" ]
}

@test "config_tool_command: ツールの command を取得" {
  run config_tool_command claude
  [ "$output" = "claude" ]
}

@test "config_tool_enabled: claude は有効 (exit 0)" {
  run config_tool_enabled claude
  [ "$status" -eq 0 ]
}

@test "config_tool_enabled: codex は無効 (exit 非0)" {
  run config_tool_enabled codex
  [ "$status" -ne 0 ]
}

@test "config_sound_enabled: soundEnabled=true (exit 0)" {
  run config_sound_enabled
  [ "$status" -eq 0 ]
}

@test "config_sound_path: USERPROFILE を展開" {
  run config_sound_path claude
  [ "$output" = "$HOME/alert.mp3" ]
}

@test "config_sound_path: 未定義 tool は空かつ exit 0 (set -e 安全)" {
  run config_sound_path nosuchtool
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "config_recent_history_path: USERPROFILE を展開" {
  run config_recent_history_path
  [ "$output" = "$HOME/.ai-startup/recent.json" ]
}

@test "config_require: 妥当な config で成功" {
  run config_require
  [ "$status" -eq 0 ]
}

@test "config_require: 不正 JSON で失敗" {
  echo 'broken{' > "$AI_STARTUP_CONFIG_PATH"
  run config_require
  [ "$status" -ne 0 ]
}

@test "config_require: config 不在で失敗" {
  # 二重 source ガードで common.sh は再評価されないため CCSU_CONFIG_PATH を直接上書き
  CCSU_CONFIG_PATH="$TEST_TEMP/nope.json"
  run config_require
  [ "$status" -ne 0 ]
}

@test "config_project_list: dir+.git のみ列挙 (ファイル/非Git/隠し除外)" {
  local base="$TEST_TEMP/pl"
  mkdir -p "$base/RepoA/.git" "$base/RepoB/.git" "$base/PlainDir"
  touch "$base/file.md" "$base/.hidden"
  printf '{ "projects": "%s" }\n' "$base" > "$TEST_TEMP/pl-config.json"
  CCSU_CONFIG_PATH="$TEST_TEMP/pl-config.json"
  run config_project_list
  [[ "$output" == *"RepoA"* ]]
  [[ "$output" == *"RepoB"* ]]
  [[ "$output" != *"PlainDir"* ]]
  [[ "$output" != *"file.md"* ]]
  [[ "$output" != *".hidden"* ]]
}
