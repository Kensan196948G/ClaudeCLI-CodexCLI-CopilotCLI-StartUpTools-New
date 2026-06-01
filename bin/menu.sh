#!/usr/bin/env bash
# ============================================================
# menu.sh — 運用管理メニュー TUI (Linux native)
#
# 移植元: scripts/main/Start-Menu.ps1
# 方針: 番号体系・配置・色・絵文字・罫線を維持 (見た目を変えない)。
#   変更点 (ユーザー合意済み):
#     S1: ☁️SSH自律 → 🌙ローカルBG自律 (番号維持・意味更新)
#     L1: 🖥️ローカル即起動 → フォアグラウンド明記
#     項6: 💾ドライブマッピング診断 → 💾マウント/NW疎通診断
#     項7: ⚙️Windows Terminal → ⚙️tmux/端末セットアップ
#     接続表示: SSH前提 → ローカルパス中心
#
# テスト: menu.sh --render で show_menu を1回描画して終了 (突合/bats用)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/../lib/json.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"
# shellcheck source=lib/launcher-common.sh
source "$SCRIPT_DIR/../lib/launcher-common.sh"

CCSU_STATE_FILE="${CCSU_STATE_FILE:-$CCSU_ROOT/state.json}"
BIN="$SCRIPT_DIR"
LIBEXEC="$CCSU_ROOT/libexec"

menu__phase_mode()   { json_get "$CCSU_STATE_FILE" '.maintenance.phase_mode' 'development'; }
menu__deploy_ready() { json_get "$CCSU_STATE_FILE" '.deploy.ready' 'false'; }

show_menu() {
  clear 2>/dev/null || true
  local mode deploy_ready is_maint=0 local_dir
  mode="$(menu__phase_mode)"
  deploy_ready="$(menu__deploy_ready)"
  [[ "$mode" == "maintenance" || "$mode" == "released" ]] && is_maint=1
  local_dir="$(config_projects_dir)"

  local phase_label phase_color
  case "$mode" in
    maintenance) phase_label="保守・運用中 (maintenance)"; phase_color="$C_GREEN" ;;
    released)    phase_label="リリース済み (released)";    phase_color="$C_GREEN" ;;
    *)           phase_label="開発中 (development)";        phase_color="$C_CYAN" ;;
  esac
  local deploy_badge=""
  [[ "$deploy_ready" == "true" && $is_maint -eq 0 ]] && deploy_badge=" 🚀 デプロイ準備完了!"

  printf '\n'
  printf '  %s╔══════════════════════════════════════════════════╗%s\n' "$C_CYAN" "$C_RESET"
  printf '  %s║  🤖 ClaudeCode スタートアップツール v3.3 (Linux) ║%s\n' "$C_CYAN" "$C_RESET"
  printf '  %s╚══════════════════════════════════════════════════╝%s\n' "$C_CYAN" "$C_RESET"
  printf '  %s📋 フェーズ: %s%s%s%s\n' "$C_GRAY" "$C_RESET" "$phase_color" "$phase_label$deploy_badge" "$C_RESET"
  printf '  %s📂 %s%s%s\n' "$C_GREEN" "$C_DKGREEN" "$local_dir" "$C_RESET"
  printf '\n'

  # 起動
  printf '  %s🚀 %s起動%s\n' "$C_CYAN" "$C_DKCYAN" "$C_RESET"
  printf '   %s L1 %s  🖥️  ローカル即起動 (フォアグラウンド)\n' "$C_BG_GREEN" "$C_RESET"
  printf '   %s S1 %s  🌙 バックグラウンド起動 (自律 / 5h)\n' "$C_BG_YELLOW" "$C_RESET"
  printf '\n'

  if (( is_maint == 0 )); then
    printf '  %s🚢 デプロイ管理%s\n' "$C_BLUE" "$C_RESET"
    printf '   %s  DP%s  🚀 デプロイ準備（Runbook生成・前提チェック）\n' "$C_BG_BLUE" "$C_RESET"
    printf '   %s  M %s  🔄 保守モードへ移行（リリース完了後）\n' "$C_BG_DKCYAN" "$C_RESET"
    printf '\n'
  else
    printf '  %s🛡️  保守・運用%s\n' "$C_GREEN" "$C_RESET"
    printf '   %s  I %s  🚨 インシデント対応（P1/P2/P3トリアージ）\n' "$C_BG_RED" "$C_RESET"
    printf '   %s  W %s  📊 週次 DevOps レポート確認\n' "$C_BG_GREEN" "$C_RESET"
    printf '\n'
  fi

  # 診断・ツール
  printf '  %s🔧 診断・ツール%s\n' "$C_MAGENTA" "$C_RESET"
  local item
  for item in \
    " 5  🩺 ツール確認・診断" \
    " 6  💾 マウント / ネットワーク疎通診断" \
    " 7  ⚙️  tmux / 端末セットアップ" \
    " 8  🩹 MCP ヘルスチェック" \
    " 9  🤝 Agent Teams ランタイム" \
    "10  🌿 Worktree Manager" \
    "11  🏛️  Architecture Check" \
    "12  📊 Statusline 設定" \
    "13  📡 Claude ログ監視 (tmux/tail)" \
    "16  🤝 Agent Teams Status (CLI 表示)" \
    "PD  🌐 Projects Dashboard (進捗 WebUI)" \
    "MC  🎛️  Mission Control (統合管理)" \
    "DR  📌 Dashboard を自動起動に登録 (systemd/cron)" \
    "DU  🗑️  Dashboard 自動起動を解除"; do
    printf '    %s%s%s\n' "$C_MAGENTA" "$item" "$C_RESET"
  done
  printf '\n'

  # Cron
  printf '  %s⏰ Linux Cron 管理%s\n' "$C_YELLOW" "$C_RESET"
  printf '   %s 14 %s  📅  Cron スケジュール 登録・編集・削除\n' "$C_BG_DKBLUE" "$C_RESET"
  printf '   %s 15 %s  📺  セッション状態監視 (tmux / リアルタイム)\n' "$C_BG_DKBLUE" "$C_RESET"
  printf '\n'

  local hr; hr="  $(printf '─%.0s' {1..52})"
  printf '%s%s%s\n' "$C_GRAY" "$hr" "$C_RESET"
  printf '    0  ❌  終了\n'
  printf '%s%s%s\n\n' "$C_GRAY" "$hr" "$C_RESET"
}

# run_menu_script <file> [args...] — 実行し非0なら logs/menu-error-*.log 生成 (Invoke-MenuScript 相当)
run_menu_script() {
  local file="$1"; shift
  if [[ ! -f "$file" ]]; then
    log_warn "未実装 (Phase 3 後続で追加予定): $(basename "$file")"
    read -rp "  Enter で戻る " _ || true
    return 0
  fi
  if ! bash "$file" "$@"; then
    local rc=$? ts; ts="$(date +%Y%m%d-%H%M%S)"; mkdir -p "$CCSU_ROOT/logs"
    { echo "Timestamp: $ts"; echo "Script: $file"; echo "Args: $*"; echo "ExitCode: $rc"; echo "Host: $(hostname)"; } \
      > "$CCSU_ROOT/logs/menu-error-$ts.log"
    printf '%s  エラー (終了コード %s) — logs/menu-error-%s.log%s\n' "$C_RED" "$rc" "$ts" "$C_RESET"
  fi
  read -rp "  Enter で戻る " _ || true
}

# L1/S1: プロジェクト選択 → start-claude.sh
launch_claude() {
  local mode="$1" project
  project="$(launcher__select_project)"
  [[ -n "$project" ]] || { log_warn "プロジェクト未選択"; sleep 1; return 0; }
  run_menu_script "$BIN/start-claude.sh" --project "$project" "--$mode"
}

menu_loop() {
  while true; do
    show_menu
    local choice; read -rp "  番号を入力してください: " choice
    case "${choice^^}" in
      L1) launch_claude foreground ;;
      S1) launch_claude background ;;
      DP) run_menu_script "$BIN/deploy-prep.sh" ;;
      M)  run_menu_script "$BIN/maintenance-mode.sh" ;;
      I)  run_menu_script "$BIN/incident-response.sh" ;;
      W)  run_menu_script "$BIN/weekly-devops.sh" ;;
      5)  run_menu_script "$LIBEXEC/diag-all-tools.sh" ;;
      6)  run_menu_script "$LIBEXEC/diag-mounts.sh" ;;
      7)  run_menu_script "$LIBEXEC/setup-terminal.sh" ;;
      8)  run_menu_script "$LIBEXEC/diag-mcp-health.sh" ;;
      9)  run_menu_script "$LIBEXEC/diag-agent-teams.sh" ;;
      10) run_menu_script "$LIBEXEC/diag-worktree.sh" ;;
      11) run_menu_script "$LIBEXEC/diag-architecture.sh" ;;
      12) run_menu_script "$BIN/set-statusline.sh" ;;
      13) run_menu_script "$LIBEXEC/watch-claude-log.sh" ;;
      14) run_menu_script "$BIN/cron-schedule.sh" ;;
      15) bash "$LIBEXEC/watch-session.sh" || true ;;   # 内部に 0=戻る の対話メニューを持つため直接実行
      16) if [[ -f "$CCSU_ROOT/scripts/tools/agent-teams-status.js" ]]; then
            ( cd "$CCSU_ROOT" && node scripts/tools/agent-teams-status.js ) || true
          else log_warn "agent-teams-status.js が見つかりません"; fi
          read -rp "  Enter で戻る " _ || true ;;
      PD) run_menu_script "$BIN/start-dashboard.sh" ;;
      MC) run_menu_script "$BIN/start-dashboard.sh" --no-browser ;;
      DR) run_menu_script "$BIN/dashboard-service.sh" --register --run-now ;;
      DU) run_menu_script "$BIN/dashboard-service.sh" --unregister ;;
      0)  exit 0 ;;
      *)  printf '%s  無効な入力です。%s\n' "$C_RED" "$C_RESET"; sleep 1 ;;
    esac
  done
}

main() {
  case "${1:-menu}" in
    --render) show_menu ;;          # 1回描画して終了 (突合/bats用)
    menu|"")  menu_loop ;;
    *) log_error "不明な引数: $1"; exit 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
