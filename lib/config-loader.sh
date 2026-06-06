#!/usr/bin/env bash
# ============================================================
# config-loader.sh — config.json アクセサ (Linux native)
#
# 役割: scripts/lib/ConfigLoader.ps1 + Config.psm1 + LauncherCommon.psm1 の
#       Import-LauncherConfig / Get-StartupConfigPath 相当。
#       config.json の各値を意味のある関数名で取り出す薄いラッパ。
#
# 設計: Linux ローカル一本化のため projectsDir(Windows: D:\) より
#       projects(/home/kensan/Projects) を優先する。
#
# 前提: json.sh (jq) を source。
# ============================================================

[[ -n "${_CCSU_CONFIG_LOADED:-}" ]] && return 0
_CCSU_CONFIG_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/json.sh"

# --- 汎用アクセサ ---
# config_get <jq-filter> [default]
config_get()     { json_get "$CCSU_CONFIG_PATH" "$1" "${2:-}"; }
# config_get_raw <jq-filter>  (配列/オブジェクト)
config_get_raw() { json_get_raw "$CCSU_CONFIG_PATH" "$1"; }

# --- プロジェクトディレクトリ (ローカル一本化: projects 優先) ---
config_projects_dir() {
  local base
  base="$(config_get '.projects' '')"
  if [[ -n "$base" ]]; then printf '%s' "$base"; else config_get '.projectsDir' "$HOME/Projects"; fi
}

# --- プロジェクト列挙 (正本) ---
#   条件: config_projects_dir 直下の「ディレクトリ かつ Git リポジトリ(.git 保有)」のみ。
#   ファイル・非 Git ディレクトリ・隠しエントリは除外。出力は名前を 1 行 1 件 (名前順)。
#   ※ */ グロブがディレクトリのみ・隠し除外を満たすため、.md/.sh/.json 等は自然に落ちる。
config_project_list() {
  local base; base="$(config_projects_dir)"
  [[ -d "$base" ]] || return 0
  local d
  for d in "$base"/*/; do
    [[ -d "$d" ]] || continue         # マッチ無し時の literal "*/" 対策
    [[ -d "${d}.git" ]] || continue   # Git リポジトリのみ (.git サブディレクトリ保有)
    basename "$d"
  done
}

config_linux_user() { config_get '.linuxUser' "$USER"; }

# --- ツール定義 ---
config_default_tool()  { config_get '.tools.defaultTool' 'claude'; }
config_tool_command()  { config_get ".tools.$1.command" "$1"; }
# config_tool_enabled <tool> — bool (enabled==true なら 0)
config_tool_enabled()  { [[ "$(config_get ".tools.$1.enabled" 'false')" == 'true' ]]; }

# --- 通知音 (notify.sh が使用。WinMM→ffplay 置換の設定源) ---
# config_sound_enabled — bool
config_sound_enabled() { [[ "$(config_get '.notifications.soundEnabled' 'false')" == 'true' ]]; }
# config_sound_path <tool> — 音声ファイルパス (%USERPROFILE%/\ を Linux 化)
config_sound_path() {
  local p; p="$(config_get ".notifications.sounds.$1" '')"
  [[ -z "$p" ]] && return 0          # 未定義 tool は空 + exit 0 (set -e 安全)
  json_expand_path "$p"
}

# --- Recent Projects 履歴パス (%USERPROFILE% 展開) ---
config_recent_history_path() {
  local p; p="$(config_get '.recentProjects.historyFile' '')"
  if [[ -n "$p" ]]; then json_expand_path "$p"; else printf '%s' "$HOME/.ai-startup/recent-projects.json"; fi
}

# --- config 妥当性確認 (実行エントリ用。不在/不正 JSON で終了) ---
config_require() {
  [[ -f "$CCSU_CONFIG_PATH" ]] || die "config が見つかりません: $CCSU_CONFIG_PATH"
  json_valid "$CCSU_CONFIG_PATH" || die "config が不正な JSON です: $CCSU_CONFIG_PATH"
}
