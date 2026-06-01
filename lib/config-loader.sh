#!/usr/bin/env bash
# ============================================================
# config-loader.sh — config.json アクセサ (Linux native)
#
# 役割: scripts/lib/ConfigLoader.ps1 + Config.psm1 + LauncherCommon.psm1 の
#       Import-LauncherConfig / Get-StartupConfigPath 相当。
#       config.json の各値を意味のある関数名で取り出す薄いラッパ。
#
# 設計: Linux ローカル一本化のため projectsDir(Windows: D:\) より
#       linuxBase(/home/kensan/Projects) を優先する。
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

# --- プロジェクトディレクトリ (ローカル一本化: linuxBase 優先) ---
config_projects_dir() {
  local base
  base="$(config_get '.linuxBase' '')"
  if [[ -n "$base" ]]; then printf '%s' "$base"; else config_get '.projectsDir' "$HOME/Projects"; fi
}

# --- 接続情報 (移行後はローカル実行のため参考値) ---
config_linux_host() { config_get '.linuxHost' ''; }
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
  [[ -n "$p" ]] && json_expand_path "$p"
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
