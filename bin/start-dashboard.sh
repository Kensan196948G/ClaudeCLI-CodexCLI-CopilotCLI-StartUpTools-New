#!/usr/bin/env bash
# ============================================================
# start-dashboard.sh — Mission Control / Projects Dashboard 起動 (Linux native)
#
# 移植元: scripts/main/Start-Dashboard.ps1
# 保持: scripts/dashboards/serve-dashboard.js (Node.js, 無改修。0.0.0.0 で listen)
#
# 改善: SSH/ヘッドレス環境では xdg-open(localhost) が効かないため、
#   LAN IP を自動検出して Windows 等からアクセスできる URL を案内する。
#   ポート使用中なら「既に起動中」として URL 案内のみ (二重起動防止)。
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

  local ip url
  ip="$(ccsu_lan_ip)"
  url="http://$ip:$port/mission-control"

  # 既存起動チェック: ポート使用中なら起動済みとみなし URL を案内 (二重起動防止)
  if ss -ltn 2>/dev/null | grep -q ":$port "; then
    log_ok "Dashboard は既に起動中です (port $port)"
    printf '  %sWindows のブラウザで:%s %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_GREEN" "$url" "$C_RESET"
    return 0
  fi

  export AI_STARTUP_PROJECTS_DIR; AI_STARTUP_PROJECTS_DIR="$(config_projects_dir)"
  log_ok "Dashboard 起動: port $port (0.0.0.0)"
  printf '  %sWindows のブラウザで:%s %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_GREEN" "$url" "$C_RESET"
  log_info "(このターミナルを閉じると停止します。常駐は DR / dashboard-service.sh --register)"

  if (( no_browser == 0 )) && command -v xdg-open >/dev/null 2>&1; then
    ( sleep 2; xdg-open "$url" >/dev/null 2>&1 || true ) &
  fi

  cd "$CCSU_ROOT"
  exec node "$dash" "$port"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
