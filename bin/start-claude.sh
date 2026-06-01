#!/usr/bin/env bash
# ============================================================
# start-claude.sh — ClaudeCode 起動エントリ (Linux native)
#
# 移植元: scripts/main/Start-ClaudeCode.ps1 の「ローカル分岐のみ」
#   廃止: SSH デプロイ / base64 配布 / PTY bridge (約400行) → ローカル実行に一本化
#   多重起動防止: Named Mutex → tmux has-session (tmux_run 内)
#
# 使い方 (menu.sh から):
#   start-claude.sh --project P --foreground [--duration 300]   # L1: tmux attach
#   start-claude.sh --project P --background [--duration 300]   # S1: detached
#   --local は互換用 (ローカル一本化のため常にローカル)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"
# shellcheck source=lib/launcher-common.sh
source "$SCRIPT_DIR/../lib/launcher-common.sh"
# shellcheck source=lib/tmux-runner.sh
source "$SCRIPT_DIR/../lib/tmux-runner.sh"
# shellcheck source=lib/notify.sh
source "$SCRIPT_DIR/../lib/notify.sh"

main() {
  local project="" mode="foreground" duration=300
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)    project="$2"; shift 2 ;;
      --foreground) mode="foreground"; shift ;;
      --background) mode="background"; shift ;;
      --duration)   duration="$2"; shift 2 ;;
      --local)      shift ;;   # 互換: ローカル一本化のため無視
      *) log_error "不明な引数: $1"; exit 1 ;;
    esac
  done

  require_cmd claude "npm i -g @anthropic-ai/claude-code"

  [[ -z "$project" ]] && project="$(launcher__select_project)"
  [[ -n "$project" ]] || { log_error "プロジェクトが選択されていません"; exit 1; }
  launcher__project_exists "$project" || { log_error "プロジェクトが存在しません: $(launcher__project_dir "$project")"; exit 1; }

  notify__play claude   # 起動通知音 (非ブロッキング・失敗無害)
  tmux_run "$project" "$duration" "$mode"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
