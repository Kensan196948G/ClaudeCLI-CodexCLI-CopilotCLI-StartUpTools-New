#!/usr/bin/env bash
# ============================================================
# docker-control.sh — 登録プロジェクトの Docker 統合制御 CLI (Linux native)
#
# /home/kensan/Projects 配下の登録プロジェクトを Docker から起動・管理する。
# 検出/台帳/Hub 連携の実体は lib/docker-manager.sh。本ファイルは CLI 表層。
#
# 使い方:
#   docker-control.sh status                  # Docker 可用性・compose・login 状態
#   docker-control.sh scan                     # Projects 走査 (compose/stack/登録状況)
#   docker-control.sh list                     # 台帳の登録プロジェクト一覧
#   docker-control.sh register <name> [--compose REL] [--no-autostart]
#   docker-control.sh unregister <name>
#   docker-control.sh up   <name>              # compose up -d
#   docker-control.sh down <name>              # compose down
#   docker-control.sh ps   <name>              # compose ps
#   docker-control.sh logs <name> [args...]    # compose logs (既定 --tail=100)
#   docker-control.sh up-all                   # autostart=true を一括起動
#   docker-control.sh scaffold <name> [--force]# stack 検出で Dockerfile/compose 雛形生成
#   docker-control.sh login-status             # login 検出のみ (未ログインは手動案内)
#   docker-control.sh hub-images [namespace]   # Docker Hub のリポジトリ一覧
#   docker-control.sh hub-pull <image>         # イメージ取得
#   docker-control.sh help
#
# 設計上の厳守事項:
#   - docker のインストールおよび `docker login` は決して自動実行しない。
#     未ログイン時は `! docker login` の手動実行をユーザーへ案内するのみ。
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"
# shellcheck source=lib/docker-manager.sh
source "$SCRIPT_DIR/../lib/docker-manager.sh"

# ------------------------------------------------------------
# 表示ヘルパ
# ------------------------------------------------------------
_mark() { [[ "$1" -eq 0 ]] && printf '%s✅%s' "$C_GREEN" "$C_RESET" || printf '%s❌%s' "$C_RED" "$C_RESET"; }

# ------------------------------------------------------------
# status — Docker 環境の総合診断 (read-only)
# ------------------------------------------------------------
dc__status() {
  printf '%s📦 Docker 環境診断%s\n' "$C_CYAN" "$C_RESET"

  local cli_ok=1 daemon_ok=1
  docker_cli_present && cli_ok=0
  printf '  %s docker CLI       %s\n' "$(_mark "$cli_ok")" "$( (( cli_ok == 0 )) && command -v docker || echo '未インストール (手動: 公式手順)')"

  if (( cli_ok == 0 )); then
    printf '  ℹ️  client version  %s\n' "$(docker_version 2>/dev/null || echo '?')"
  fi

  docker_daemon_up && daemon_ok=0
  printf '  %s docker daemon    %s\n' "$(_mark "$daemon_ok")" "$( (( daemon_ok == 0 )) && echo '到達OK' || echo '未到達 (sudo systemctl start docker など — 手動)')"

  local cc; cc="$(docker_compose_cmd)"
  if [[ -n "$cc" ]]; then
    printf '  ✅ compose         %s\n' "$cc"
  else
    printf '  ❌ compose         利用不可 (docker compose プラグイン未導入)\n'
  fi

  if docker_logged_in; then
    printf '  ✅ registry login  ログイン済み (user: %s)\n' "$(docker_hub_user 2>/dev/null || echo '?')"
  else
    printf '  ⚠️  registry login  未ログイン — 必要なら %s! docker login%s を手動実行\n' "$C_YELLOW" "$C_RESET"
  fi

  printf '  📁 台帳            %s (%s 件登録)\n' "$DOCKER_REGISTRY_PATH" "$(docker_registry_projects | grep -c . || true)"
}

# ------------------------------------------------------------
# scan — Projects 配下を走査し compose/stack/登録状況を一覧
# ------------------------------------------------------------
dc__scan() {
  local base; base="$(config_projects_dir)"
  printf '%s🔍 プロジェクト走査%s (%s)\n' "$C_CYAN" "$C_RESET" "$base"
  printf '  %-32s %-10s %-26s %-8s %s\n' 'PROJECT' 'STACK' 'COMPOSE' '登録' 'AUTOSTART'
  printf '  %s\n' '----------------------------------------------------------------------------------------'
  local name dir stack compose reg autostart
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    dir="$(docker_project_dir "$name")"
    stack="$(docker_detect_stack "$dir")"
    compose="$(docker_find_compose "$dir")"
    [[ -z "$compose" ]] && compose='-'
    if docker_registry_has "$name"; then
      reg='yes'
      autostart="$(docker_registry_get "$name" 'autostart' 'false')"
    else
      reg='-'; autostart='-'
    fi
    printf '  %-32s %-10s %-26s %-8s %s\n' "$name" "$stack" "$compose" "$reg" "$autostart"
  done < <(config_project_list)
}

# ------------------------------------------------------------
# list — 台帳の登録プロジェクト一覧
# ------------------------------------------------------------
dc__list() {
  local n; n="$(docker_registry_projects | grep -c . || true)"
  if [[ "$n" -eq 0 ]]; then
    log_info "台帳に登録されたプロジェクトはありません ($DOCKER_REGISTRY_PATH)"
    log_info "登録: docker-control.sh register <name>"
    return 0
  fi
  printf '%s📋 Docker 管理台帳%s (%s 件)\n' "$C_CYAN" "$C_RESET" "$n"
  printf '  %-32s %-10s %-26s %s\n' 'PROJECT' 'STACK' 'COMPOSE' 'AUTOSTART'
  printf '  %s\n' '------------------------------------------------------------------------------'
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    printf '  %-32s %-10s %-26s %s\n' \
      "$name" \
      "$(docker_registry_get "$name" 'stack' '?')" \
      "$(docker_registry_get "$name" 'compose' '-')" \
      "$(docker_registry_get "$name" 'autostart' 'false')"
  done < <(docker_registry_projects)
}

# ------------------------------------------------------------
# register / unregister
# ------------------------------------------------------------
dc__register() {
  local name="" compose="" autostart="true"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --compose)      compose="$2"; shift 2 ;;
      --no-autostart) autostart="false"; shift ;;
      --*)            log_error "register: 不明な引数: $1"; return 1 ;;
      *)              name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || { log_error "register: <name> は必須"; return 1; }
  docker_registry_register "$name" "$compose" "$autostart" || return 1
  local c; c="$(docker_registry_get "$name" 'compose' '')"
  if [[ -z "$c" || "$c" == "null" ]]; then
    log_ok "登録: $name (compose 未検出 — scaffold で雛形生成可: docker-control.sh scaffold $name)"
  else
    log_ok "登録: $name (compose=$c, stack=$(docker_registry_get "$name" 'stack' '?'), autostart=$autostart)"
  fi
}

dc__unregister() {
  local name="${1:-}"
  [[ -n "$name" ]] || { log_error "unregister: <name> は必須"; return 1; }
  docker_registry_has "$name" || { log_warn "未登録: $name"; return 0; }
  docker_registry_unregister "$name"
  log_ok "登録解除: $name"
}

# ------------------------------------------------------------
# register-all — compose 検出済みかつ未登録のプロジェクトを一括登録
#   既存・今後新規の両方を拾う。compose 不在は scaffold 候補として報告のみ。
#   既定 autostart=false (一括起動の暴発防止)。--autostart で true 化。
# ------------------------------------------------------------
dc__register_all() {
  local autostart="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --autostart) autostart="true"; shift ;;
      --*)         log_error "register-all: 不明な引数: $1"; return 1 ;;
      *)           log_error "register-all: 余分な引数: $1"; return 1 ;;
    esac
  done
  local added=0 skipped=0 scaffoldable=0 name dir compose
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if docker_registry_has "$name"; then
      skipped=$((skipped + 1)); continue
    fi
    dir="$(docker_project_dir "$name")"
    compose="$(docker_find_compose "$dir")"
    if [[ -z "$compose" ]]; then
      scaffoldable=$((scaffoldable + 1))
      log_info "  scaffold 候補: $name (compose 不在 — scaffold $name で雛形生成可)"
      continue
    fi
    if docker_registry_register "$name" "$compose" "$autostart"; then
      added=$((added + 1))
      log_ok "登録: $name (compose=$compose, autostart=$autostart)"
    else
      log_warn "登録失敗: $name (継続)"
    fi
  done < <(config_project_list)
  printf '%s📊 一括登録結果%s 追加=%d 既登録=%d scaffold候補=%d\n' \
    "$C_CYAN" "$C_RESET" "$added" "$skipped" "$scaffoldable"
  return 0
}

# ------------------------------------------------------------
# サービス制御 (compose 経由) — docker 可用性を先に確認
# ------------------------------------------------------------
dc__require_docker() {
  docker_available && return 0
  log_error "Docker が利用できません (CLI 不在 or daemon 未到達)。status で確認してください"
  log_info "  インストール/起動はユーザー手動対応 (このツールは自動化しません)"
  return 1
}

dc__up() {
  local name="${1:-}"; [[ -n "$name" ]] || { log_error "up: <name> は必須"; return 1; }
  dc__require_docker || return 1
  log_info "🚀 起動: $name"
  docker_up "$name"
}

dc__down() {
  local name="${1:-}"; [[ -n "$name" ]] || { log_error "down: <name> は必須"; return 1; }
  dc__require_docker || return 1
  log_info "🛑 停止: $name"
  docker_down "$name"
}

dc__ps() {
  local name="${1:-}"; [[ -n "$name" ]] || { log_error "ps: <name> は必須"; return 1; }
  dc__require_docker || return 1
  docker_ps "$name"
}

dc__logs() {
  local name="${1:-}"; [[ -n "$name" ]] || { log_error "logs: <name> は必須"; return 1; }
  shift
  dc__require_docker || return 1
  docker_logs "$name" "$@"
}

dc__up_all() {
  dc__require_docker || return 1
  local any=0 name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    any=1
    log_info "🚀 起動 (autostart): $name"
    docker_up "$name" || log_warn "起動失敗: $name (継続)"
  done < <(docker_registry_autostart_list)
  (( any == 0 )) && log_info "autostart=true のプロジェクトはありません"
  return 0
}

# ------------------------------------------------------------
# login-status — 検出のみ。未ログインは手動案内 (自動ログイン禁止)
# ------------------------------------------------------------
dc__login_status() {
  if docker_logged_in; then
    log_ok "Docker registry ログイン済み (user: $(docker_hub_user 2>/dev/null || echo '?'))"
    printf '  config: %s\n' "$(docker_config_json)"
  else
    log_warn "Docker registry に未ログインです"
    printf '  Docker Hub と連携するには、以下を%s手動%sで実行してください:\n' "$C_YELLOW" "$C_RESET"
    printf '    %s! docker login%s\n' "$C_CYAN" "$C_RESET"
    printf '  (このツールは認証情報を扱わず、ログインを自動化しません)\n'
  fi
}

# ------------------------------------------------------------
# Docker Hub 連携
# ------------------------------------------------------------
dc__hub_images() {
  local ns="${1:-}"
  printf '%s🐳 Docker Hub リポジトリ一覧%s%s\n' "$C_CYAN" "$C_RESET" "${ns:+ ($ns)}"
  local rows
  rows="$(docker_hub_list_images "$ns")" || return 1
  if [[ -z "$rows" ]]; then
    log_info "リポジトリが見つかりません (公開リポジトリのみ無認証で列挙されます)"
    return 0
  fi
  printf '  %-40s %-12s %s\n' 'REPOSITORY' 'PULLS' 'VISIBILITY'
  printf '  %s\n' '----------------------------------------------------------------'
  local repo pulls vis
  while IFS=$'\t' read -r repo pulls vis; do
    printf '  %-40s %-12s %s\n' "$repo" "$pulls" "$vis"
  done <<< "$rows"
}

dc__hub_pull() {
  local image="${1:-}"
  [[ -n "$image" ]] || { log_error "hub-pull: <image> は必須 (例: user/repo:tag)"; return 1; }
  dc__require_docker || return 1
  log_info "⬇️  pull: $image"
  if ! docker_hub_pull "$image"; then
    log_error "pull に失敗しました。private イメージの場合は %s! docker login%s を手動実行してください" "$C_YELLOW" "$C_RESET"
    return 1
  fi
}

# ------------------------------------------------------------
# scaffold — stack 検出で Dockerfile/compose 雛形を <project>/docker/ に生成
#   非破壊: 既存 compose があれば全体スキップ。個別ファイルも存在時スキップ。
#   --force で上書き。
# ------------------------------------------------------------
# _scaffold_write <path> <force> — heredoc を受けてファイルを書く (非破壊)
_scaffold_write() {
  local path="$1" force="$2"
  if [[ -f "$path" && "$force" != "1" ]]; then
    log_info "  skip (既存): ${path#"$(config_projects_dir)"/}"
    return 1
  fi
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  log_ok "  生成: ${path#"$(config_projects_dir)"/}"
  return 0
}

dc__scaffold() {
  local name="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      --*)     log_error "scaffold: 不明な引数: $1"; return 1 ;;
      *)       name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || { log_error "scaffold: <name> は必須"; return 1; }

  local dir; dir="$(docker_project_dir "$name")"
  [[ -d "$dir" ]] || { log_error "プロジェクトが見つかりません: $dir"; return 1; }

  if docker_has_compose "$dir" && (( force == 0 )); then
    log_warn "既に compose が存在します: $(docker_find_compose "$dir") — scaffold をスキップ (--force で再生成)"
    return 0
  fi

  local stack; stack="$(docker_detect_stack "$dir")"
  log_info "🧱 scaffold: $name (stack=$stack) → $dir/docker/"

  case "$stack" in
    fullstack) _scaffold_fullstack "$dir" "$force" ;;
    node)      _scaffold_node "$dir" "$force" ;;
    python)    _scaffold_python "$dir" "$force" ;;
    static)    _scaffold_static "$dir" "$force" ;;
    *)
      log_warn "stack=$stack の雛形は未対応です。汎用 compose のみ生成します"
      _scaffold_generic "$dir" "$force" ;;
  esac

  log_info "  生成物を確認し、ポート/環境変数/起動コマンドを調整してから register/up してください"
}

_scaffold_node() {
  local dir="$1" force="$2"
  _scaffold_write "$dir/docker/Dockerfile" "$force" <<'EOF' || true
# syntax=docker/dockerfile:1
# Node.js アプリ用 雛形 (調整前提)
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY . .
ENV NODE_ENV=production
EXPOSE 3000
# TODO: 実際の起動コマンドへ調整
CMD ["node", "index.js"]
EOF
  _scaffold_write "$dir/docker/docker-compose.yml" "$force" <<'EOF' || true
# Docker Compose 雛形 (調整前提) — context はプロジェクトルート
services:
  app:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    ports:
      - "3000:3000"   # TODO: 実ポートへ
    environment:
      - NODE_ENV=production
    restart: unless-stopped
EOF
}

_scaffold_python() {
  local dir="$1" force="$2"
  _scaffold_write "$dir/docker/Dockerfile" "$force" <<'EOF' || true
# syntax=docker/dockerfile:1
# Python アプリ用 雛形 (調整前提)
FROM python:3.12-slim
WORKDIR /app
COPY . .
# requirements.txt / pyproject.toml いずれにも対応 (どちらか存在する方を採用)
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; \
    elif [ -f pyproject.toml ]; then pip install --no-cache-dir .; \
    else echo "WARN: 依存定義なし (requirements.txt/pyproject.toml)"; fi
EXPOSE 8000
# TODO: 実際の起動コマンドへ調整 (uvicorn/gunicorn/flask 等)
CMD ["python", "main.py"]
EOF
  _scaffold_write "$dir/docker/docker-compose.yml" "$force" <<'EOF' || true
# Docker Compose 雛形 (調整前提) — context はプロジェクトルート
services:
  app:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    ports:
      - "8000:8000"   # TODO: 実ポートへ
    restart: unless-stopped
EOF
}

_scaffold_static() {
  local dir="$1" force="$2"
  _scaffold_write "$dir/docker/Dockerfile" "$force" <<'EOF' || true
# syntax=docker/dockerfile:1
# 静的サイト用 雛形 (nginx 配信)
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
EOF
  _scaffold_write "$dir/docker/docker-compose.yml" "$force" <<'EOF' || true
# Docker Compose 雛形 (静的サイト) — context はプロジェクトルート
services:
  web:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    ports:
      - "8080:80"   # TODO: 実ポートへ
    restart: unless-stopped
EOF
}

_scaffold_fullstack() {
  local dir="$1" force="$2"
  _scaffold_write "$dir/docker/Dockerfile.backend" "$force" <<'EOF' || true
# syntax=docker/dockerfile:1
# バックエンド (Python) 雛形 — context はプロジェクトルート
FROM python:3.12-slim
WORKDIR /app
COPY backend/ .
# requirements.txt / pyproject.toml いずれにも対応
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; \
    elif [ -f pyproject.toml ]; then pip install --no-cache-dir .; \
    else echo "WARN: 依存定義なし (requirements.txt/pyproject.toml)"; fi
EXPOSE 8000
# TODO: 実際の起動コマンドへ調整 (uvicorn/gunicorn/flask 等)
CMD ["python", "main.py"]
EOF
  _scaffold_write "$dir/docker/Dockerfile.frontend" "$force" <<'EOF' || true
# syntax=docker/dockerfile:1
# フロントエンド 雛形 — context はプロジェクトルート
# 2 ステージ構成: build (Node) → 配信 (nginx)。Vite/Vue/React を想定
# --- build stage ---
FROM node:20-alpine AS build
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci || npm install
COPY frontend/ .
# build script があればビルド (Vite=dist / CRA=build)。無ければ空 dist を用意して停止回避
RUN npm run build || (echo "WARN: build script なし — 空 dist を生成"; mkdir -p dist)
# --- serve stage ---
FROM nginx:alpine
# TODO: ビルド出力先が build/ の場合は /app/dist を /app/build に変更
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
# nginx はベースイメージのデフォルト CMD で起動するため CMD 不要
EOF
  _scaffold_write "$dir/docker/docker-compose.yml" "$force" <<'EOF' || true
# Docker Compose 雛形 (フルスタック) — context はプロジェクトルート
services:
  backend:
    build:
      context: ..
      dockerfile: docker/Dockerfile.backend
    ports:
      - "8000:8000"   # TODO: 実ポートへ
    restart: unless-stopped
  frontend:
    build:
      context: ..
      dockerfile: docker/Dockerfile.frontend
    ports:
      - "3000:80"     # nginx(80) をホスト 3000 へ公開。TODO: 実ポートへ
    depends_on:
      - backend
    restart: unless-stopped
EOF
}

_scaffold_generic() {
  local dir="$1" force="$2"
  _scaffold_write "$dir/docker/docker-compose.yml" "$force" <<'EOF' || true
# Docker Compose 雛形 (汎用) — stack 自動判定不可。手動で image/build を指定してください
services:
  app:
    # build: { context: .., dockerfile: docker/Dockerfile }  # ビルドする場合
    image: alpine:latest   # TODO: 実イメージ or build へ置換
    command: ["sh", "-c", "echo 'edit docker/docker-compose.yml'; sleep infinity"]
    restart: unless-stopped
EOF
}

# ------------------------------------------------------------
# help
# ------------------------------------------------------------
dc__help() {
  cat <<'EOF'
📦 docker-control.sh — 登録プロジェクトの Docker 統合制御

  status                          Docker 可用性・compose・login 状態を診断
  scan                            Projects 走査 (compose/stack/登録状況)
  list                            台帳の登録プロジェクト一覧
  register <name> [opts]          台帳へ登録   --compose REL / --no-autostart
  register-all [--autostart]      compose 検出済み未登録を一括登録 (既存+今後新規)
  unregister <name>               台帳から解除
  up <name>                       compose up -d
  down <name>                     compose down
  ps <name>                       compose ps
  logs <name> [args...]           compose logs (既定 --tail=100)
  up-all                          autostart=true を一括起動
  scaffold <name> [--force]       stack 検出で Dockerfile/compose 雛形生成
  login-status                    login 検出のみ (未ログインは手動案内)
  hub-images [namespace]          Docker Hub のリポジトリ一覧
  hub-pull <image>                イメージ取得
  help                            このヘルプ

  ⚠️ docker のインストールと `docker login` は自動化しません。
     未ログイン時は `! docker login` を手動実行してください。
EOF
}

# ------------------------------------------------------------
# dispatch
# ------------------------------------------------------------
main() {
  case "${1:-help}" in
    status)       dc__status ;;
    scan)         dc__scan ;;
    list)         dc__list ;;
    register)     shift; dc__register "$@" ;;
    register-all) shift; dc__register_all "$@" ;;
    unregister)   shift; dc__unregister "$@" ;;
    up)           shift; dc__up "$@" ;;
    down)         shift; dc__down "$@" ;;
    ps)           shift; dc__ps "$@" ;;
    logs)         shift; dc__logs "$@" ;;
    up-all)       dc__up_all ;;
    scaffold)     shift; dc__scaffold "$@" ;;
    login-status) dc__login_status ;;
    hub-images)   shift; dc__hub_images "${1:-}" ;;
    hub-pull)     shift; dc__hub_pull "${1:-}" ;;
    help|-h|--help|"") dc__help ;;
    *) log_error "不明なサブコマンド: $1"; dc__help; exit 1 ;;
  esac
}

# 直接実行時のみ main を呼ぶ (source 時=テストでは呼ばない)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
