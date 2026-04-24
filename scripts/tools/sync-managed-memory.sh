#!/usr/bin/env bash
# =============================================================================
# sync-managed-memory.sh — Linux 用 Memory Store 同期スクリプト
# Sync-ManagedMemory.ps1 (Windows) と同等の機能を Bash で提供する。
#
# Usage:
#   sync-managed-memory.sh push        # ローカル .md → Memory Store (デフォルト)
#   sync-managed-memory.sh pull        # Memory Store → ローカル .md
#   sync-managed-memory.sh list        # ストア内メモリ一覧
#   sync-managed-memory.sh write /path/to/mem.md   # 1件書き込み (stdin から content)
#   sync-managed-memory.sh status      # 設定状態確認
#
# 環境変数:
#   ANTHROPIC_API_KEY        — Anthropic Workspace API キー (必須)
#   MANAGED_MEMORY_DIR       — ローカルメモリディレクトリ上書き (省略可)
#   MANAGED_AGENTS_CONFIG    — config JSON パス上書き (省略可)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANAGED_MEMORY_PY="$SCRIPT_DIR/managed-memory.py"

# Python3 の存在確認
if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 が見つかりません" >&2
    exit 1
fi

# config パス (環境変数で上書き可能)
export MANAGED_AGENTS_CONFIG="${MANAGED_AGENTS_CONFIG:-$PROJECT_ROOT/config/managed-agents.json}"

# API キーが未設定で config に apiKey がある場合は config から取得
if [[ -z "${ANTHROPIC_API_KEY:-}" ]] && [[ -f "$MANAGED_AGENTS_CONFIG" ]]; then
    ANTHROPIC_API_KEY="$(python3 -c "
import json, sys
try:
    d = json.load(open('$MANAGED_AGENTS_CONFIG'))
    print(d.get('apiKey',''))
except: print('')
" 2>/dev/null || true)"
    export ANTHROPIC_API_KEY
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "[ERROR] ANTHROPIC_API_KEY が未設定です" >&2
    echo "  ~/.env-claudeos に ANTHROPIC_API_KEY=sk-ant-api03-... を追加してください" >&2
    exit 1
fi

DIRECTION="${1:-push}"

case "$DIRECTION" in
    push|pull)
        echo "[Memory] sync ($DIRECTION) ..."
        python3 "$MANAGED_MEMORY_PY" sync --direction "$DIRECTION"
        ;;
    list)
        python3 "$MANAGED_MEMORY_PY" list
        ;;
    write)
        PATH_ARG="${2:-}"
        if [[ -z "$PATH_ARG" ]]; then
            echo "[ERROR] write には /path/to/memory.md が必要です" >&2
            exit 1
        fi
        CONTENT="$(cat)"  # stdin から読む
        python3 "$MANAGED_MEMORY_PY" write --path "$PATH_ARG" --content "$CONTENT"
        ;;
    status)
        python3 "$MANAGED_MEMORY_PY" status
        ;;
    *)
        echo "Usage: $0 {push|pull|list|write|status}" >&2
        exit 1
        ;;
esac
