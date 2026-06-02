#!/usr/bin/env bash
# ============================================================
# dashboard-service.sh — Dashboard 自動起動 登録/解除 (メニュー項DR/DU)
# 移植元: scripts/main/Register-DashboardTask.ps1 (Windows タスクスケジューラ)
#   → systemd user service を第一候補、不可なら crontab @reboot フォールバック
#
# CCSU_SYSTEMCTL_BIN で systemctl を差し替え可 (bats スタブ用)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"

UNIT="claudeos-dashboard.service"
UNIT_PATH="${CCSU_SYSTEMD_UNIT_PATH:-$HOME/.config/systemd/user/$UNIT}"
SYSTEMCTL="${CCSU_SYSTEMCTL_BIN:-systemctl}"
CRONTAB_BIN="${CCSU_CRONTAB_BIN:-crontab}"

ds__register() {
  if ! has_cmd "$SYSTEMCTL"; then
    log_warn "systemd (systemctl) が無いため crontab @reboot を使用します"
    ds__register_cron; return
  fi
  mkdir -p "$(dirname "$UNIT_PATH")"
  local node dash pdir
  node="$(command -v node || echo /usr/bin/node)"
  dash="$CCSU_ROOT/scripts/dashboards/serve-dashboard.js"
  pdir="$(config_projects_dir)"
  cat > "$UNIT_PATH" <<EOF
[Unit]
Description=ClaudeOS Dashboard (Mission Control)
After=network.target

[Service]
Type=simple
WorkingDirectory=$CCSU_ROOT
Environment=AI_STARTUP_PROJECTS_DIR=$pdir
ExecStart=$node $dash 3737
Restart=on-failure

[Install]
WantedBy=default.target
EOF
  "$SYSTEMCTL" --user daemon-reload
  "$SYSTEMCTL" --user enable --now "$UNIT"
  command -v loginctl >/dev/null 2>&1 && (loginctl enable-linger "$USER" 2>/dev/null || true)
  log_ok "systemd user service 登録: $UNIT (http://localhost:3737)"
}

ds__register_cron() {
  local pdir cmd
  pdir="$(config_projects_dir)"
  cmd="@reboot cd $CCSU_ROOT && AI_STARTUP_PROJECTS_DIR=$pdir node scripts/dashboards/serve-dashboard.js 3737 >> $HOME/.claudeos/logs/dashboard.log 2>&1"
  ( "$CRONTAB_BIN" -l 2>/dev/null | grep -v 'serve-dashboard.js' || true; printf '%s\n' "$cmd" ) | "$CRONTAB_BIN" -
  log_ok "crontab @reboot 登録 (systemd 代替)"
}

ds__unregister() {
  if has_cmd "$SYSTEMCTL"; then
    "$SYSTEMCTL" --user disable --now "$UNIT" 2>/dev/null || true
    rm -f "$UNIT_PATH"
    "$SYSTEMCTL" --user daemon-reload 2>/dev/null || true
  fi
  if has_cmd "$CRONTAB_BIN"; then
    "$CRONTAB_BIN" -l 2>/dev/null | grep -v 'serve-dashboard.js' | "$CRONTAB_BIN" - 2>/dev/null || true
  fi
  log_ok "Dashboard 自動起動を解除しました"
}

main() {
  local action=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --register)   action="register"; shift ;;
      --unregister) action="unregister"; shift ;;
      --run-now)    shift ;;   # systemd enable --now で兼ねる
      --status)     action="status"; shift ;;
      *) log_error "不明な引数: $1"; exit 1 ;;
    esac
  done
  case "$action" in
    register)   ds__register ;;
    unregister) ds__unregister ;;
    status)     "$SYSTEMCTL" --user status "$UNIT" --no-pager 2>/dev/null || echo "(未登録)" ;;
    *) log_error "--register / --unregister / --status のいずれかを指定"; exit 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
