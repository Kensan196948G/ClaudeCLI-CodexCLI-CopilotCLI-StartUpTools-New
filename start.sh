#!/usr/bin/env bash
# ============================================================
# start.sh — ClaudeOS 起動エントリ (start.bat 相当 / Linux native)
#   運用管理メニュー (bin/menu.sh) を起動する。
#   引数はそのまま menu.sh へ渡す (例: --render)。
# ============================================================

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/bin/menu.sh" "$@"
