#!/usr/bin/env bash
# ============================================================
# start-dashboard.sh — Mission Control / Projects Dashboard 起動 (Linux native)
#
# 移植元: scripts/main/Start-Dashboard.ps1
# 保持: scripts/dashboards/serve-dashboard.js (Node.js, 無改修)
#   Start-Process http://... → xdg-open
#
# 使い方: start-dashboard.sh [--no-browser] [--port N]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"

main() {
  local no_browser=0 port=3737
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-browser) no_browser=1; shift ;;
      --port) port="$2"; shift 2 ;;
      *) log_error "不明な引数: $1"; exit 1 ;;
    esac
  done

  require_cmd node "npm が必要: https://nodejs.org"
  local dash="$CCSU_ROOT/scripts/dashboards/serve-dashboard.js"
  [[ -f "$dash" ]] || { log_error "serve-dashboard.js が見つかりません: $dash"; exit 1; }

  # serve-dashboard.js はこの環境変数でプロジェクトディレクトリを参照
  export AI_STARTUP_PROJECTS_DIR; AI_STARTUP_PROJECTS_DIR="$(config_projects_dir)"

  if (( no_browser == 0 )) && command -v xdg-open >/dev/null 2>&1; then
    ( sleep 2; xdg-open "http://localhost:$port" >/dev/null 2>&1 || true ) &
  fi

  log_info "Dashboard 起動: http://localhost:$port/mission-control (Ctrl-C で停止)"
  cd "$CCSU_ROOT"
  exec node "$dash" "$port"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
