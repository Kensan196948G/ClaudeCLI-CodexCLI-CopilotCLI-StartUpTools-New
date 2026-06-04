#!/usr/bin/env bats
# ============================================================
# docker-manager.bats — lib/docker-manager.sh のユニットテスト
#
# 範囲: daemon 非依存の純関数のみ検証する。
#   - compose 検出 (docker_find_compose / docker_has_compose)
#   - スタック検出 (docker_detect_stack)
#   - 台帳 CRUD (docker_registry_*)
#   - login 状態の検出 (docker_logged_in / docker_hub_user) ※DETECT ONLY
#
# 除外: docker info / compose 実行 (up/down/ps/logs)・Hub API は
#       daemon / ネットワーク依存のため対象外。
#
# 設計上の注意:
#   - CCSU_DOCKER_REGISTRY と AI_STARTUP_CONFIG_PATH は source 前に export する
#     (DOCKER_REGISTRY_PATH / CCSU_CONFIG_PATH は読み込み時に確定するため)。
#   - autostart=false は jq の `false // empty` 罠で json_get が空になるため、
#     真偽の検証は docker_registry_autostart_list (select で厳密比較) で行う。
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup

  # config: linuxBase を一時 projects ディレクトリに向ける
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  printf '{ "linuxBase": "%s" }\n' "$TEST_TEMP/projects" > "$AI_STARTUP_CONFIG_PATH"
  mkdir -p "$TEST_TEMP/projects"

  # 台帳: 一時パスへ差し替え
  export CCSU_DOCKER_REGISTRY="$TEST_TEMP/docker-registry.json"

  # docker config: 既定で「未ログイン」を保証 (存在しないパス)
  export DOCKER_CONFIG="$TEST_TEMP/dockercfg"

  source "$REPO_ROOT/lib/docker-manager.sh"
}
teardown() { _bats_common_teardown; }

# --- ヘルパ: 一時プロジェクトを作る ---
_mkproj() { mkdir -p "$TEST_TEMP/projects/$1"; }

# ============================================================
# docker_find_compose / docker_has_compose
# ============================================================

@test "docker_find_compose: ルートの docker-compose.yml を検出" {
  _mkproj Root
  touch "$TEST_TEMP/projects/Root/docker-compose.yml"
  run docker_find_compose "$TEST_TEMP/projects/Root"
  [ "$status" -eq 0 ]
  [ "$output" = "docker-compose.yml" ]
}

@test "docker_find_compose: docker/ サブディレクトリを検出" {
  _mkproj Sub
  mkdir -p "$TEST_TEMP/projects/Sub/docker"
  touch "$TEST_TEMP/projects/Sub/docker/docker-compose.yml"
  run docker_find_compose "$TEST_TEMP/projects/Sub"
  [ "$output" = "docker/docker-compose.yml" ]
}

@test "docker_find_compose: ルートがサブディレクトリより優先" {
  _mkproj Pri
  mkdir -p "$TEST_TEMP/projects/Pri/docker"
  touch "$TEST_TEMP/projects/Pri/compose.yml"
  touch "$TEST_TEMP/projects/Pri/docker/docker-compose.yml"
  run docker_find_compose "$TEST_TEMP/projects/Pri"
  [ "$output" = "compose.yml" ]
}

@test "docker_find_compose: 同一ディレクトリでは docker-compose.yml が compose.yml より優先" {
  _mkproj Ord
  touch "$TEST_TEMP/projects/Ord/compose.yml"
  touch "$TEST_TEMP/projects/Ord/docker-compose.yml"
  run docker_find_compose "$TEST_TEMP/projects/Ord"
  [ "$output" = "docker-compose.yml" ]
}

@test "docker_find_compose: infra/docker と deploy も探索する" {
  _mkproj Infra
  mkdir -p "$TEST_TEMP/projects/Infra/infra/docker"
  touch "$TEST_TEMP/projects/Infra/infra/docker/compose.yaml"
  run docker_find_compose "$TEST_TEMP/projects/Infra"
  [ "$output" = "infra/docker/compose.yaml" ]

  _mkproj Dep
  mkdir -p "$TEST_TEMP/projects/Dep/deploy"
  touch "$TEST_TEMP/projects/Dep/deploy/docker-compose.yaml"
  run docker_find_compose "$TEST_TEMP/projects/Dep"
  [ "$output" = "deploy/docker-compose.yaml" ]
}

@test "docker_find_compose: compose なしは空・exit 0" {
  _mkproj Empty
  run docker_find_compose "$TEST_TEMP/projects/Empty"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "docker_find_compose: 存在しないディレクトリは空・exit 0" {
  run docker_find_compose "$TEST_TEMP/projects/NoSuchDir"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "docker_has_compose: 有無で 0/非0 を返す" {
  _mkproj Has
  touch "$TEST_TEMP/projects/Has/docker-compose.yml"
  run docker_has_compose "$TEST_TEMP/projects/Has"
  [ "$status" -eq 0 ]

  _mkproj Hasnt
  run docker_has_compose "$TEST_TEMP/projects/Hasnt"
  [ "$status" -ne 0 ]
}

# ============================================================
# docker_detect_stack
# ============================================================

@test "docker_detect_stack: node (package.json)" {
  _mkproj N
  touch "$TEST_TEMP/projects/N/package.json"
  run docker_detect_stack "$TEST_TEMP/projects/N"
  [ "$output" = "node" ]
}

@test "docker_detect_stack: python (requirements.txt)" {
  _mkproj P
  touch "$TEST_TEMP/projects/P/requirements.txt"
  run docker_detect_stack "$TEST_TEMP/projects/P"
  [ "$output" = "python" ]
}

@test "docker_detect_stack: python (pyproject.toml)" {
  _mkproj Pp
  touch "$TEST_TEMP/projects/Pp/pyproject.toml"
  run docker_detect_stack "$TEST_TEMP/projects/Pp"
  [ "$output" = "python" ]
}

@test "docker_detect_stack: fullstack (frontend node + backend python)" {
  _mkproj F
  mkdir -p "$TEST_TEMP/projects/F/frontend" "$TEST_TEMP/projects/F/backend"
  touch "$TEST_TEMP/projects/F/frontend/package.json"
  touch "$TEST_TEMP/projects/F/backend/requirements.txt"
  run docker_detect_stack "$TEST_TEMP/projects/F"
  [ "$output" = "fullstack" ]
}

@test "docker_detect_stack: go (go.mod)" {
  _mkproj G
  touch "$TEST_TEMP/projects/G/go.mod"
  run docker_detect_stack "$TEST_TEMP/projects/G"
  [ "$output" = "go" ]
}

@test "docker_detect_stack: rust (Cargo.toml)" {
  _mkproj R
  touch "$TEST_TEMP/projects/R/Cargo.toml"
  run docker_detect_stack "$TEST_TEMP/projects/R"
  [ "$output" = "rust" ]
}

@test "docker_detect_stack: static (index.html のみ)" {
  _mkproj S
  touch "$TEST_TEMP/projects/S/index.html"
  run docker_detect_stack "$TEST_TEMP/projects/S"
  [ "$output" = "static" ]
}

@test "docker_detect_stack: 何もなければ unknown" {
  _mkproj U
  run docker_detect_stack "$TEST_TEMP/projects/U"
  [ "$output" = "unknown" ]
}

@test "docker_detect_stack: 存在しないディレクトリは unknown・exit 0" {
  run docker_detect_stack "$TEST_TEMP/projects/Ghost"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

# ============================================================
# 台帳 CRUD (docker_registry_*)
# ============================================================

@test "docker_registry_ensure: スケルトンを生成 (_comment + 空 projects)" {
  run docker_registry_ensure
  [ "$status" -eq 0 ]
  [ -f "$CCSU_DOCKER_REGISTRY" ]
  run jq -r '._comment' "$CCSU_DOCKER_REGISTRY"
  [[ "$output" == *"台帳"* ]]
  run jq -r '.projects | length' "$CCSU_DOCKER_REGISTRY"
  [ "$output" = "0" ]
}

@test "docker_registry_has: 登録前は非0" {
  docker_registry_ensure
  run docker_registry_has Alpha
  [ "$status" -ne 0 ]
}

@test "docker_registry_register: 登録後に has=0 + フィールド取得" {
  _mkproj Alpha
  touch "$TEST_TEMP/projects/Alpha/package.json"
  touch "$TEST_TEMP/projects/Alpha/docker-compose.yml"
  run docker_registry_register Alpha
  [ "$status" -eq 0 ]

  run docker_registry_has Alpha
  [ "$status" -eq 0 ]

  run docker_registry_get Alpha compose
  [ "$output" = "docker-compose.yml" ]

  run docker_registry_get Alpha stack
  [ "$output" = "node" ]
}

@test "docker_registry_register: 存在しないプロジェクトは失敗 (非0)" {
  run docker_registry_register Ghost
  [ "$status" -ne 0 ]
}

@test "docker_registry_get: 未登録フィールドは既定値を返す" {
  docker_registry_ensure
  run docker_registry_get Missing stack NOPE
  [ "$output" = "NOPE" ]
}

@test "docker_registry_projects: 名前順で列挙" {
  _mkproj Bravo; _mkproj Alpha; _mkproj Charlie
  docker_registry_register Bravo '' false
  docker_registry_register Alpha '' false
  docker_registry_register Charlie '' false
  run docker_registry_projects
  [ "${lines[0]}" = "Alpha" ]
  [ "${lines[1]}" = "Bravo" ]
  [ "${lines[2]}" = "Charlie" ]
}

@test "docker_registry_autostart_list: autostart=true のみ抽出" {
  _mkproj OnA; _mkproj OffB
  docker_registry_register OnA '' true
  docker_registry_register OffB '' false
  run docker_registry_autostart_list
  [[ "$output" == *"OnA"* ]]
  [[ "$output" != *"OffB"* ]]
}

@test "docker_registry_register: autostart 省略時は既定 true" {
  _mkproj DefA
  docker_registry_register DefA
  run docker_registry_autostart_list
  [[ "$output" == *"DefA"* ]]
}

@test "docker_registry_unregister: 削除後に has=非0" {
  _mkproj Del
  docker_registry_register Del '' false
  run docker_registry_has Del
  [ "$status" -eq 0 ]

  docker_registry_unregister Del
  run docker_registry_has Del
  [ "$status" -ne 0 ]
}

# ============================================================
# login 状態の検出 (DETECT ONLY — 決してログインしない)
# ============================================================

@test "docker_logged_in: config なしは非0 (未ログイン)" {
  run docker_logged_in
  [ "$status" -ne 0 ]
}

@test "docker_logged_in: auths に登録があれば 0 (ログイン済み)" {
  mkdir -p "$DOCKER_CONFIG"
  printf '{ "auths": { "https://index.docker.io/v1/": { "auth": "x" } } }\n' \
    > "$DOCKER_CONFIG/config.json"
  run docker_logged_in
  [ "$status" -eq 0 ]
}

@test "docker_logged_in: auths が空配列なら非0" {
  mkdir -p "$DOCKER_CONFIG"
  printf '{ "auths": {} }\n' > "$DOCKER_CONFIG/config.json"
  run docker_logged_in
  [ "$status" -ne 0 ]
}

@test "docker_hub_user: DOCKER_HUB_USER 環境変数を優先" {
  DOCKER_HUB_USER=myhubuser run docker_hub_user
  [ "$output" = "myhubuser" ]
}
