#!/usr/bin/env bash
# ============================================================
# docker-manager.sh — 登録プロジェクトの Docker 統合管理 (Linux native)
#
# 役割: /home/kensan/Projects 配下の登録プロジェクトに対し、
#   - Docker 資産 (compose / Dockerfile) の検出
#   - Docker からのサービス起動/停止/状態/ログ
#   - 管理対象プロジェクトの台帳 (config/docker-registry.json) 管理
#   - スタック検出ベースの雛形 (Dockerfile/compose) 生成
#   - 同一アカウントの Docker Hub 連携 (イメージ一覧・pull)
#   を提供する。
#
# 設計方針 (厳守):
#   - docker login は「検出のみ」。本ライブラリは決してログインを自動化しない。
#     認証が必要な場合は呼び出し側がユーザーへ `docker login` の手動実行を促す。
#   - docker のインストールも自動実行しない (冪等な存在確認のみ)。
#
# 前提: common.sh / json.sh / config-loader.sh を source。
#       docker CLI は実行エントリ側で存在確認すること
#       (このライブラリは source 時に exit しない方針 = set -e なし)。
# ============================================================

[[ -n "${_CCSU_DOCKER_LOADED:-}" ]] && return 0
_CCSU_DOCKER_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/json.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config-loader.sh"

# --- 台帳パス (テスト時は CCSU_DOCKER_REGISTRY で差し替え) ---
DOCKER_REGISTRY_PATH="${CCSU_DOCKER_REGISTRY:-$CCSU_ROOT/config/docker-registry.json}"

# ------------------------------------------------------------
# Docker 可用性
# ------------------------------------------------------------
# docker_cli_present — docker バイナリが PATH にあれば 0
docker_cli_present() { has_cmd docker; }

# docker_daemon_up — デーモンに到達できれば 0 (docker info が成功)
docker_daemon_up() { docker info >/dev/null 2>&1; }

# docker_available — CLI 在 + デーモン到達の両方を満たせば 0
docker_available() { docker_cli_present && docker_daemon_up; }

# docker_version — クライアントバージョン (取得不可なら空)
docker_version() { docker_cli_present || return 0; docker version --format '{{.Server.Version}}' 2>/dev/null || true; }

# ------------------------------------------------------------
# compose コマンド解決 (v2 プラグイン優先 / v1 standalone フォールバック)
#   echo: "docker compose" | "docker-compose" | "" (いずれも無し)
# ------------------------------------------------------------
docker_compose_cmd() {
  if docker_cli_present && docker compose version >/dev/null 2>&1; then
    printf 'docker compose'
  elif has_cmd docker-compose; then
    printf 'docker-compose'
  else
    printf ''
  fi
}

# ------------------------------------------------------------
# login 状態の検出 (DETECT ONLY — 決してログインしない)
# ------------------------------------------------------------
# docker_config_json — ~/.docker/config.json のパス
docker_config_json() { printf '%s' "${DOCKER_CONFIG:-$HOME/.docker}/config.json"; }

# docker_logged_in — auths に 1 件以上の登録があれば 0 (= 何らかの registry にログイン済み)
docker_logged_in() {
  local cfg; cfg="$(docker_config_json)"
  [[ -f "$cfg" ]] || return 1
  local n; n="$(jq -r '(.auths // {}) | length' "$cfg" 2>/dev/null || echo 0)"
  [[ "${n:-0}" -gt 0 ]]
}

# docker_hub_user — Docker Hub のユーザー名を可能な範囲で推定 (検出のみ)
#   優先: 環境変数 DOCKER_HUB_USER → config.json auths の docker.io 由来 → docker info
docker_hub_user() {
  if [[ -n "${DOCKER_HUB_USER:-}" ]]; then printf '%s' "$DOCKER_HUB_USER"; return 0; fi
  local cfg; cfg="$(docker_config_json)"
  if [[ -f "$cfg" ]]; then
    local u
    u="$(jq -r '(.auths // {}) | keys[] | select(test("docker.io|index.docker.io"))' "$cfg" 2>/dev/null | head -1 || true)"
    # auths のキーは registry ホストなのでユーザー名そのものは入らない。
    # ユーザー名は info の Username に出ることがある。
  fi
  docker_cli_present || { printf ''; return 0; }
  docker info 2>/dev/null | sed -n 's/^ *Username: *//p' | head -1
}

# ------------------------------------------------------------
# compose ファイル検出
#   探索順 (primary = 最初に見つかった接尾辞なしの基本ファイル):
#     1. <dir>/docker-compose.yml | .yaml
#     2. <dir>/compose.yml | .yaml
#     3. <dir>/docker/docker-compose.yml | .yaml
#     4. <dir>/infra/docker/docker-compose.yml | .yaml
#     5. <dir>/deploy/docker-compose.yml | .yaml
#   echo: プロジェクトルートからの相対パス (見つからなければ空・exit 0)
# ------------------------------------------------------------
docker_find_compose() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  local sub f
  for sub in '.' 'docker' 'infra/docker' 'deploy'; do
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
      local rel
      if [[ "$sub" == '.' ]]; then rel="$f"; else rel="$sub/$f"; fi
      if [[ -f "$dir/$rel" ]]; then printf '%s' "$rel"; return 0; fi
    done
  done
  printf ''
}

# docker_has_compose <dir> — compose を持てば 0
docker_has_compose() { [[ -n "$(docker_find_compose "$1")" ]]; }

# docker_project_dir <name> — 登録プロジェクトの絶対パス
docker_project_dir() { printf '%s/%s' "$(config_projects_dir)" "$1"; }

# docker_project_compose <name> — 登録プロジェクト名から primary compose 相対パスを得る
docker_project_compose() { docker_find_compose "$(docker_project_dir "$1")"; }

# ------------------------------------------------------------
# スタック検出 (雛形生成の入力)
#   echo: node | python | fullstack | go | rust | dotnet | java-maven |
#         java-gradle | php | ruby | static | unknown
#   fullstack = backend(python) + frontend(node) の典型構成
# ------------------------------------------------------------
docker_detect_stack() {
  local dir="$1"
  [[ -d "$dir" ]] || { printf 'unknown'; return 0; }
  local has_node=0 has_py=0
  [[ -f "$dir/package.json" || -f "$dir/frontend/package.json" || -f "$dir/web/package.json" ]] && has_node=1
  [[ -f "$dir/requirements.txt" || -f "$dir/pyproject.toml" || -f "$dir/backend/requirements.txt" || -f "$dir/backend/pyproject.toml" ]] && has_py=1

  if (( has_node == 1 && has_py == 1 )); then printf 'fullstack'; return 0; fi
  if (( has_py == 1 )); then printf 'python'; return 0; fi
  if (( has_node == 1 )); then printf 'node'; return 0; fi

  if [[ -f "$dir/go.mod" ]]; then printf 'go'; return 0; fi
  if [[ -f "$dir/Cargo.toml" ]]; then printf 'rust'; return 0; fi
  if compgen -G "$dir/*.csproj" >/dev/null 2>&1 || compgen -G "$dir/*.sln" >/dev/null 2>&1; then printf 'dotnet'; return 0; fi
  if [[ -f "$dir/pom.xml" ]]; then printf 'java-maven'; return 0; fi
  if [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" ]]; then printf 'java-gradle'; return 0; fi
  if [[ -f "$dir/composer.json" ]]; then printf 'php'; return 0; fi
  if [[ -f "$dir/Gemfile" ]]; then printf 'ruby'; return 0; fi
  if [[ -f "$dir/index.html" ]]; then printf 'static'; return 0; fi
  printf 'unknown'
}

# ------------------------------------------------------------
# 台帳 (config/docker-registry.json) CRUD
#   形: { "_comment": "...", "projects": { "<name>": {compose, autostart, stack, registered_at} } }
# ------------------------------------------------------------
# docker_registry_ensure — 不在ならスケルトンを生成
docker_registry_ensure() {
  [[ -f "$DOCKER_REGISTRY_PATH" ]] && return 0
  json_set "$DOCKER_REGISTRY_PATH" \
    '{_comment: $c, projects: {}}' \
    --arg c "Docker 管理対象プロジェクト台帳。docker-control.sh が読み書きする。compose=primary compose 相対パス, autostart=メニュー/cron 一括起動の対象, stack=検出スタック。"
}

# docker_registry_projects — 登録済みプロジェクト名 (1 行 1 件・名前順)
docker_registry_projects() {
  [[ -f "$DOCKER_REGISTRY_PATH" ]] || return 0
  jq -r '(.projects // {}) | keys[]' "$DOCKER_REGISTRY_PATH" 2>/dev/null | sort || true
}

# docker_registry_has <name> — 登録済みなら 0
docker_registry_has() {
  [[ -f "$DOCKER_REGISTRY_PATH" ]] || return 1
  local v; v="$(jq -r --arg n "$1" '(.projects // {}) | has($n)' "$DOCKER_REGISTRY_PATH" 2>/dev/null || echo false)"
  [[ "$v" == "true" ]]
}

# docker_registry_get <name> <field> [default] — 単一フィールド取得
docker_registry_get() {
  local name="$1" field="$2" default="${3:-}"
  json_get "$DOCKER_REGISTRY_PATH" ".projects[\"$name\"].$field" "$default"
}

# docker_registry_register <name> [compose_rel] [autostart_bool]
#   compose_rel 省略時は自動検出。autostart 省略時は true。
docker_registry_register() {
  local name="$1" compose="${2:-}" autostart="${3:-true}"
  [[ -n "$name" ]] || { log_warn "register: プロジェクト名が空です"; return 1; }
  local dir; dir="$(docker_project_dir "$name")"
  [[ -d "$dir" ]] || { log_warn "register: プロジェクトが見つかりません: $dir"; return 1; }
  [[ -z "$compose" ]] && compose="$(docker_find_compose "$dir")"
  local stack; stack="$(docker_detect_stack "$dir")"
  local now; now="$(date -Iseconds)"
  docker_registry_ensure
  json_set "$DOCKER_REGISTRY_PATH" \
    '.projects[$n] = {compose: $c, autostart: ($a == "true"), stack: $s, registered_at: $t}' \
    --arg n "$name" --arg c "$compose" --arg a "$autostart" --arg s "$stack" --arg t "$now"
}

# docker_registry_unregister <name>
docker_registry_unregister() {
  local name="$1"
  [[ -f "$DOCKER_REGISTRY_PATH" ]] || return 0
  json_set "$DOCKER_REGISTRY_PATH" 'del(.projects[$n])' --arg n "$name"
}

# docker_registry_autostart_list — autostart=true のプロジェクト名
docker_registry_autostart_list() {
  [[ -f "$DOCKER_REGISTRY_PATH" ]] || return 0
  jq -r '(.projects // {}) | to_entries[] | select(.value.autostart == true) | .key' \
    "$DOCKER_REGISTRY_PATH" 2>/dev/null | sort || true
}

# ------------------------------------------------------------
# サービス制御 (compose 経由)
#   各関数は compose ファイルの相対パスを台帳 or 自動検出で解決し、
#   プロジェクトディレクトリを作業基準として compose を実行する。
# ------------------------------------------------------------
# _docker_resolve_compose <name> — 台帳の compose を優先、無ければ自動検出。echo: 相対パス
_docker_resolve_compose() {
  local name="$1" rel
  rel="$(docker_registry_get "$name" 'compose' '')"
  [[ -z "$rel" || "$rel" == "null" ]] && rel="$(docker_project_compose "$name")"
  printf '%s' "$rel"
}

# _docker_compose_exec <name> <compose-subcmd...> — 解決済み compose で実行
_docker_compose_exec() {
  local name="$1"; shift
  local dir; dir="$(docker_project_dir "$name")"
  [[ -d "$dir" ]] || { log_error "プロジェクトが見つかりません: $dir"; return 1; }
  local rel; rel="$(_docker_resolve_compose "$name")"
  [[ -n "$rel" ]] || { log_error "compose ファイルが見つかりません: $name"; return 1; }
  [[ -f "$dir/$rel" ]] || { log_error "compose ファイルが存在しません: $dir/$rel"; return 1; }
  local cc; cc="$(docker_compose_cmd)"
  [[ -n "$cc" ]] || { log_error "docker compose が利用できません"; return 1; }
  # shellcheck disable=SC2086  # cc は "docker compose" の 2 語を意図的に分割
  ( cd "$dir" && $cc -f "$rel" -p "$(ccsu_safe_name "$name")" "$@" )
}

# docker_up <name> [extra args] — サービス起動 (-d デタッチ既定)
docker_up()   { local n="$1"; shift; _docker_compose_exec "$n" up -d "$@"; }
# docker_down <name> [extra args] — 停止
docker_down() { local n="$1"; shift; _docker_compose_exec "$n" down "$@"; }
# docker_ps <name> — 状態
docker_ps()   { _docker_compose_exec "$1" ps; }
# docker_logs <name> [args] — ログ (既定 --tail 100)
docker_logs() { local n="$1"; shift; _docker_compose_exec "$n" logs "${@:---tail=100}"; }

# ------------------------------------------------------------
# Docker Hub 連携 (同一アカウント)
#   公開リポジトリは無認証で列挙可能 (manual-login 制約に抵触しない)。
#   private を含めたい場合のみ任意の PAT を DOCKER_HUB_TOKEN で渡す。
# ------------------------------------------------------------
# docker_hub_list_images [namespace] — 指定 (or 推定) アカウントのリポジトリ名一覧
docker_hub_list_images() {
  local ns="${1:-$(docker_hub_user)}"
  [[ -n "$ns" ]] || { log_error "Docker Hub ユーザーを特定できません (DOCKER_HUB_USER で指定可)"; return 1; }
  has_cmd curl || { log_error "curl が必要です"; return 1; }
  local url="https://hub.docker.com/v2/repositories/${ns}/?page_size=100"
  local auth=()
  [[ -n "${DOCKER_HUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${DOCKER_HUB_TOKEN}")
  local resp
  resp="$(curl -fsSL "${auth[@]}" "$url" 2>/dev/null || true)"
  [[ -n "$resp" ]] || { log_error "Docker Hub API へ到達できません: $url"; return 1; }
  printf '%s' "$resp" | jq -r --arg ns "$ns" '
    (.results // [])[] | "\($ns)/\(.name)\t\(.pull_count // 0)\t\(if .is_private then "private" else "public" end)"
  ' 2>/dev/null || { log_error "Docker Hub 応答の解析に失敗しました"; return 1; }
}

# docker_hub_pull <image> — イメージ取得 (private で失敗したら手動 login を促すのは呼び出し側)
docker_hub_pull() {
  local image="$1"
  [[ -n "$image" ]] || { log_error "イメージ名が空です"; return 1; }
  docker_cli_present || { log_error "docker CLI が見つかりません"; return 1; }
  docker pull "$image"
}

# docker_local_images [namespace] — ローカル取得済みイメージ (namespace で絞り込み可)
docker_local_images() {
  docker_cli_present || return 0
  local ns="${1:-}"
  if [[ -n "$ns" ]]; then
    docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null | grep -E "^${ns}/" || true
  else
    docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null || true
  fi
}
