#!/usr/bin/env bash
# install-supervisor-service.sh — ClaudeOS Supervisor を systemd user service として登録する
# Usage: bash install-supervisor-service.sh [--uninstall | --status | --logs]
# 移植元: scripts/main/Register-SupervisorTask.ps1 (Windows Task Scheduler 版)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVICE_NAME="claudeos-supervisor"
SERVICE_FILE="${HOME}/.config/systemd/user/${SERVICE_NAME}.service"
NODE_BIN="${NODE_BIN:-$(command -v node 2>/dev/null || echo '')}"

echo ""
echo "==========================================="
echo "  ClaudeOS Supervisor - systemd user unit  "
echo "==========================================="
echo ""

# --- --status ---
if [[ "${1:-}" == "--status" ]]; then
  if systemctl --user is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo "  状態: RUNNING"
  elif systemctl --user is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo "  状態: STOPPED (enabled)"
  else
    echo "  状態: NOT INSTALLED"
  fi
  echo ""
  # state.json からプロセス状態を表示
  state_file="${HOME}/.claudeos/supervisor/state.json"
  if [[ -f "${state_file}" ]]; then
    echo "  --- Managed Processes ---"
    node -e "
const s = JSON.parse(require('fs').readFileSync('${state_file}','utf8'));
Object.values(s.processes).forEach(p => {
  const pid = p.pid ? ' (pid='+p.pid+')' : '';
  console.log('  ['+p.status.toUpperCase().padEnd(9)+'] '+p.name+pid);
});
" 2>/dev/null || cat "${state_file}"
  else
    echo "  [INFO] state.json 未生成 — supervisor 未起動の可能性があります。"
  fi
  echo ""
  exit 0
fi

# --- --logs ---
if [[ "${1:-}" == "--logs" ]]; then
  journalctl --user -u "${SERVICE_NAME}" -n 50 --no-pager
  exit 0
fi

# --- --uninstall ---
if [[ "${1:-}" == "--uninstall" ]]; then
  systemctl --user stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl --user disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SERVICE_FILE}"
  systemctl --user daemon-reload
  echo "  [OK] サービスを削除しました: ${SERVICE_NAME}"
  echo ""
  exit 0
fi

# --- Install ---
if [[ -z "${NODE_BIN}" ]]; then
  echo "  [ERROR] node が見つかりません。Node.js をインストールしてください。"
  exit 1
fi

DAEMON_JS="${PROJ_ROOT}/scripts/dashboards/supervisor-daemon.js"
if [[ ! -f "${DAEMON_JS}" ]]; then
  echo "  [ERROR] supervisor-daemon.js が見つかりません: ${DAEMON_JS}"
  exit 1
fi

# systemd user ユニットディレクトリを確保
mkdir -p "${HOME}/.config/systemd/user"

# サービスファイルを生成
cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=ClaudeOS Supervisor Daemon
After=network.target

[Service]
Type=simple
WorkingDirectory=${PROJ_ROOT}
ExecStart=${NODE_BIN} ${DAEMON_JS}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
EOF

echo "  [OK] サービスファイルを生成しました: ${SERVICE_FILE}"

# systemd デーモン再読み込みと有効化
systemctl --user daemon-reload
systemctl --user enable "${SERVICE_NAME}"
echo "  [OK] ログオン時の自動起動を有効化しました"

# lingering 有効化 (ログアウト後も常駐)
loginctl enable-linger "$(whoami)" 2>/dev/null && \
  echo "  [OK] lingering 有効化 (ログアウト後も継続稼働)" || \
  echo "  [WARN] lingering 有効化失敗 (loginctl が使えない環境)"

# 今すぐ起動
systemctl --user start "${SERVICE_NAME}"
echo "  [OK] 起動しました"

echo ""
echo "  state.json : ${HOME}/.claudeos/supervisor/state.json"
echo "  ログ確認   : journalctl --user -u ${SERVICE_NAME} -f"
echo "  停止       : systemctl --user stop ${SERVICE_NAME}"
echo "  アンインストール: bash ${BASH_SOURCE[0]} --uninstall"
echo ""
