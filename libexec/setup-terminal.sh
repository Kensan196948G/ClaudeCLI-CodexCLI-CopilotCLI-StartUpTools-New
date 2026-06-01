#!/usr/bin/env bash
# ============================================================
# setup-terminal.sh — tmux / 端末セットアップ (メニュー項7)
# 移植元: scripts/setup/setup-windows-terminal.ps1 を Linux 向けに転用
#   (Windows Terminal プロファイル → tmux/端末の確認と案内)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

main() {
  log_info "tmux / 端末セットアップ"
  printf '\n'
  if has_cmd tmux; then
    log_ok "tmux: $(tmux -V 2>/dev/null || echo '検出')"
  else
    log_warn "tmux 未検出 — sudo apt install tmux"
  fi

  local conf="$HOME/.tmux.conf"
  if [[ -f "$conf" ]]; then log_ok "~/.tmux.conf あり"; else log_info "~/.tmux.conf なし (tmux 既定設定で動作)"; fi

  printf '  端末: TERM=%s%s%s LANG=%s\n' "$C_GRAY" "${TERM:-未設定}" "$C_RESET" "${LANG:-未設定}"
  printf '\n  %sClaudeOS セッションへの接続:%s\n' "$C_CYAN" "$C_RESET"
  printf '    実行中一覧 : tmux ls | grep claudeos-\n'
  printf '    接続       : tmux attach -t claudeos-<project>\n'
  printf '    デタッチ   : Ctrl-b d (セッションは継続)\n'
  printf '\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
