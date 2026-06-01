#!/usr/bin/env bash
# ============================================================
# deploy-prep.sh — デプロイ準備 (メニュー項DP)
# 移植元: scripts/main/Start-DeployPrep.ps1
#   state.deploy.ready=true / runbook_generated=true / environment 設定
#   実デプロイは人間が手動 (CTO は自動実行しない)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"

STATE="${CCSU_STATE_FILE:-$CCSU_ROOT/state.json}"

main() {
  local env="staging"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env) env="$2"; shift 2 ;;
      *) log_error "不明な引数: $1"; exit 1 ;;
    esac
  done
  [[ "$env" == "staging" || "$env" == "production" ]] || { log_error "env は staging|production"; exit 1; }

  log_info "デプロイ準備 (environment=$env)"
  json_set "$STATE" '.deploy.ready = true | .deploy.runbook_generated = true | .deploy.environment = $env' --arg env "$env"
  log_ok "state.deploy.ready=true / environment=$env"
  log_info "Runbook を確認のうえ、デプロイは人間が手動実行してください (CTO は自動実行しません)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
