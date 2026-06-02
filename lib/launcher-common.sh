#!/usr/bin/env bash
# ============================================================
# launcher-common.sh — ランチャー共通関数 (Linux native)
#
# 移植元: scripts/lib/LauncherCommon.psm1 の「ローカル部分のみ」
#   廃止: Resolve-SshProjectsDir / Find-AvailableDriveLetter /
#         Get-SmbMapping / New-PSDrive / Invoke-LauncherSshScript /
#         Get-LauncherShell (pwsh 探索) — Linux ローカル実行では全て不要
#
# 提供: プロジェクト一覧/選択/パス解決 (ローカル ls ベース)
# ============================================================

[[ -n "${_CCSU_LAUNCHER_LOADED:-}" ]] && return 0
_CCSU_LAUNCHER_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config-loader.sh"

# launcher__project_list — プロジェクト列挙 (config_project_list: dir かつ Git リポジトリのみ)
launcher__project_list() { config_project_list; }

# launcher__project_dir <project> — プロジェクトの絶対パス
launcher__project_dir() { printf '%s/%s' "$(config_projects_dir)" "$1"; }

# launcher__project_exists <project> — ディレクトリが存在すれば 0
launcher__project_exists() { [[ -d "$(launcher__project_dir "$1")" ]]; }

# launcher__select_project — 対話的にプロジェクトを選ぶ。結果を stdout、案内は stderr
#   (一覧が空なら手動入力)
launcher__select_project() {
  local -a projs; mapfile -t projs < <(launcher__project_list)
  if (( ${#projs[@]} == 0 )); then
    local name; read -rp "  プロジェクト名: " name; printf '%s' "$name"; return 0
  fi
  local i
  for i in "${!projs[@]}"; do printf '  [%d] %s\n' "$((i + 1))" "${projs[$i]}" >&2; done
  local idx; read -rp "  番号: " idx
  if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#projs[@]} )); then
    printf '%s' "${projs[$((idx - 1))]}"
  fi
  return 0   # 範囲外でも空 + exit 0 (set -e 安全)
}
