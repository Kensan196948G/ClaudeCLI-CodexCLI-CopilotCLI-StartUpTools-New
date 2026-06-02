#!/usr/bin/env bash
# ============================================================
# diag-worktree.sh — Worktree Manager (メニュー項10)
# 移植元: scripts/test/Test-WorktreeManager.ps1 (git worktree list)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

main() {
  log_info "Worktree Manager"
  require_cmd git
  local repo="${CCSU_WORKTREE_REPO:-$CCSU_ROOT}"
  if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    printf '\n'
    git -C "$repo" worktree list
    printf '\n'
  else
    log_warn "git リポジトリではありません: $repo"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
