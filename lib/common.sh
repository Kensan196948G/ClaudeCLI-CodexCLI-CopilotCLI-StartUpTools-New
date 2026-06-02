#!/usr/bin/env bash
# ============================================================
# common.sh — ClaudeOS bash 共通基盤 (Linux native)
#
# 役割: 全 lib/*.sh と bin/*.sh が最初に source する土台。
#   - 二重 source 防止 (Import-Module -Force の冪等性に相当)
#   - リポジトリルート / 設定パス解決
#   - ANSI カラー定義 (Write-Host -ForegroundColor の置換)
#   - ログ関数 / コマンド存在確認 / 終了コード規約
#
# 注意: このファイルは「source される」ため set -euo pipefail を設定しない。
#       厳格モードは実行エントリ (bin/*.sh) の冒頭で宣言すること。
#       (lib 側で set -e すると bats テストや呼び出し元へ波及するため)
#
# 移植元: scripts/lib/LauncherCommon.psm1 / ErrorHandler.psm1 の共通部
# ============================================================

# --- 二重 source 防止 ---
[[ -n "${_CCSU_COMMON_LOADED:-}" ]] && return 0
_CCSU_COMMON_LOADED=1

# --- リポジトリルート解決 (lib/ から 1 階層上) ---
# PowerShell: Split-Path -Parent (Split-Path -Parent $PSScriptRoot) に相当
CCSU_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCSU_ROOT="$(cd "$CCSU_LIB_DIR/.." && pwd)"

# --- 設定パス (AI_STARTUP_CONFIG_PATH で上書き可。テストや別環境向け) ---
CCSU_CONFIG_PATH="${AI_STARTUP_CONFIG_PATH:-$CCSU_ROOT/config/config.json}"

# --- ClaudeOS ホーム (cron-launcher.sh と同じ既定 ~/.claudeos) ---
CCSU_HOME="${CLAUDEOS_HOME:-$HOME/.claudeos}"

# --- ANSI カラー (TTY のみ。CLAUDEOS_PLAIN_OUTPUT=1 で無効化=絵文字描画不可端末向け) ---
if [[ -t 1 && "${CLAUDEOS_PLAIN_OUTPUT:-0}" != "1" ]]; then
  C_RESET=$'\e[0m';   C_CYAN=$'\e[36m';    C_GREEN=$'\e[32m';   C_YELLOW=$'\e[33m'
  C_RED=$'\e[31m';    C_MAGENTA=$'\e[35m'; C_BLUE=$'\e[34m';    C_GRAY=$'\e[90m'
  C_DKCYAN=$'\e[2;36m'; C_DKBLUE=$'\e[2;34m'; C_DKGREEN=$'\e[2;32m'; C_DKMAGENTA=$'\e[2;35m'; C_DKYELLOW=$'\e[2;33m'
  C_BG_YELLOW=$'\e[30;43m'; C_BG_GREEN=$'\e[30;42m'; C_BG_BLUE=$'\e[30;44m'; C_BG_RED=$'\e[30;41m'; C_BG_DKCYAN=$'\e[30;46m'; C_BG_DKBLUE=$'\e[97;44m'
else
  C_RESET='';   C_CYAN='';    C_GREEN='';   C_YELLOW=''
  C_RED='';     C_MAGENTA=''; C_BLUE='';    C_GRAY=''
  C_DKCYAN='';  C_DKBLUE='';  C_DKGREEN=''; C_DKMAGENTA=''; C_DKYELLOW=''
  C_BG_YELLOW=''; C_BG_GREEN=''; C_BG_BLUE=''; C_BG_RED=''; C_BG_DKCYAN=''; C_BG_DKBLUE=''
fi

# --- ログ関数 (アイコン付き。CLAUDE.md §2.1 出力規約に準拠) ---
log_info()  { printf '%s[INFO]%s %s\n' "$C_CYAN"   "$C_RESET" "$*"; }
log_ok()    { printf '%s[ OK ]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
log_warn()  { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[ERR ]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }

# die <msg> — エラー出力して終了 (実行スクリプト用。lib 内では使わない)
die() { log_error "$*"; exit 1; }

# --- コマンド存在確認 (PowerShell: Get-Command / Test-LauncherCommand 相当) ---
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# require_cmd <name> [hint] — 無ければ終了 (実行スクリプト用)
require_cmd() {
  has_cmd "$1" && return 0
  local hint="${2:-}"
  if [[ -n "$hint" ]]; then
    die "必須コマンドが見つかりません: $1 ($hint)"
  else
    die "必須コマンドが見つかりません: $1"
  fi
}

# --- プロジェクト名を tmux/ファイル安全な文字列へ (cron-launcher.sh の SAFE_PROJECT と同一規則) ---
ccsu_safe_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'; }

# --- LAN IP 取得 (Windows 等からアクセスする際のホスト IP。docker bridge を除外) ---
#   デフォルトルートの src IP を優先 (= 物理 LAN の 192.168.0.x 等)。失敗時は hostname -I 先頭。
ccsu_lan_ip() {
  local ip
  ip="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1)"
  [[ -z "$ip" ]] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "${ip:-127.0.0.1}"
}

# --- 終了コード規約 (PowerShell の throw 'USER_CANCELLED' を表現) ---
EXIT_USER_CANCELLED=10
