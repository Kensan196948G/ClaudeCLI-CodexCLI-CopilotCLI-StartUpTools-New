#!/usr/bin/env bash
# =============================================================================
# deploy-managed-agents-linux.sh — Linux サーバーへの Managed Agents 設定デプロイ
#
# このスクリプトは Windows 側で setup-all 済みの設定を Linux サーバーに展開する。
# 実行場所: Linux サーバー (/home/kensan/Projects/<project>)
#
# 前提:
#   - git で最新の scripts/tools/ が展開済み
#   - ~/.env-claudeos に ANTHROPIC_API_KEY が設定済み
#   - python3 が利用可能
#
# Usage:
#   ./scripts/tools/deploy-managed-agents-linux.sh
#   ./scripts/tools/deploy-managed-agents-linux.sh --api-key sk-ant-api03-...
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/managed-agents.json"
EXAMPLE_FILE="$PROJECT_ROOT/config/managed-agents.example.json"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; exit 1; }
step() { echo -e "\n[Deploy] $1"; }

# ── API キーの取得 ───────────────────────────────────────────────────────────
step "API キーの確認"

API_KEY="${ANTHROPIC_API_KEY:-}"

# コマンドライン引数から取得
while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-key) API_KEY="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# ~/.env-claudeos から取得
if [[ -z "$API_KEY" ]] && [[ -f "$HOME/.env-claudeos" ]]; then
    source "$HOME/.env-claudeos"
    API_KEY="${ANTHROPIC_API_KEY:-}"
fi

if [[ -z "$API_KEY" ]]; then
    warn "ANTHROPIC_API_KEY が未設定です。"
    echo -n "  API キーを入力してください (sk-ant-api03-...): "
    read -r API_KEY
fi

if [[ "$API_KEY" != sk-ant-* ]]; then
    fail "無効な API キー形式です（sk-ant- で始まる必要があります）"
fi
ok "API キー確認済み: ${API_KEY:0:18}***"

# ── config ファイルの作成 ────────────────────────────────────────────────────
step "config/managed-agents.json の作成"

mkdir -p "$PROJECT_ROOT/config"

if [[ -f "$CONFIG_FILE" ]]; then
    # 既存 config の apiKey だけ更新
    python3 -c "
import json
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
cfg['apiKey'] = '$API_KEY'
with open('$CONFIG_FILE', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print('updated')
"
    ok "既存 config を更新しました: $CONFIG_FILE"
else
    # example から新規作成
    if [[ -f "$EXAMPLE_FILE" ]]; then
        python3 -c "
import json
with open('$EXAMPLE_FILE') as f:
    cfg = json.load(f)
# コメントキーを削除
cfg = {k:v for k,v in cfg.items() if not k.startswith('_')}
cfg['apiKey'] = '$API_KEY'
with open('$CONFIG_FILE', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print('created')
"
        ok "config を新規作成しました: $CONFIG_FILE"
    else
        # 最小 config を作成
        python3 -c "
import json
cfg = {'apiKey': '$API_KEY'}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print('created minimal')
"
        warn "config を最小構成で作成しました。Windows 側の store_id / agent_id を手動で設定してください。"
    fi
fi

# ── Windows 側の Resource ID を同期 ─────────────────────────────────────────
step "Windows 設定の確認"
echo "  Windows 側の managed-agents.json の ID を Linux に反映するには:"
echo "  1. Windows: config\\managed-agents.json の内容をコピー"
echo "  2. Linux:   $CONFIG_FILE に貼り付けて apiKey だけ Linux 用のものに変更"
echo ""
echo "  または SSH コピー:"
echo "  scp 192.168.0.YYY:D:/ClaudeCode-StartUpTools-New/config/managed-agents.json $CONFIG_FILE"
echo "  (その後 apiKey を Linux 用に更新)"
echo ""

# ── python3 と anthropic パッケージの確認 ─────────────────────────────────
step "Python 環境の確認"

if ! python3 -c "import anthropic" 2>/dev/null; then
    warn "anthropic パッケージが未インストールです。インストールします..."
    pip3 install anthropic --quiet || pip install anthropic --quiet
fi

ANTHROPIC_VER=$(python3 -c "import anthropic; print(anthropic.__version__)" 2>/dev/null || echo "unknown")
ok "anthropic SDK: $ANTHROPIC_VER"

# ── Memory Store への接続テスト ──────────────────────────────────────────────
step "Memory Store 接続テスト"

export ANTHROPIC_API_KEY="$API_KEY"
STATUS=$(python3 "$SCRIPT_DIR/managed-memory.py" status 2>/dev/null)
STORE_OK=$(echo "$STATUS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('store_status','none'))" 2>/dev/null || echo "none")

if [[ "$STORE_OK" == "ok" ]]; then
    STORE_ID=$(echo "$STATUS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('store_id',''))" 2>/dev/null || echo "")
    MEM_COUNT=$(echo "$STATUS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('remote_memory_count',0))" 2>/dev/null || echo "0")
    ok "Memory Store 接続成功: $STORE_ID ($MEM_COUNT 件)"
else
    warn "Memory Store 未設定または接続失敗。store_id を config に設定してください。"
fi

# ── ~/.env-claudeos に ANTHROPIC_API_KEY を追記 ──────────────────────────────
step "~/.env-claudeos への API キー登録"

ENV_FILE="$HOME/.env-claudeos"
if grep -q "ANTHROPIC_API_KEY" "$ENV_FILE" 2>/dev/null; then
    # 既存エントリを更新
    sed -i "s|^export ANTHROPIC_API_KEY=.*|export ANTHROPIC_API_KEY=$API_KEY|" "$ENV_FILE"
    sed -i "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=$API_KEY|" "$ENV_FILE"
    ok "~/.env-claudeos の ANTHROPIC_API_KEY を更新しました"
else
    echo "export ANTHROPIC_API_KEY=$API_KEY" >> "$ENV_FILE"
    ok "~/.env-claudeos に ANTHROPIC_API_KEY を追加しました"
fi

# ── まとめ ───────────────────────────────────────────────────────────────────
step "デプロイ完了"
echo ""
echo "  次のステップ:"
echo "  1. Memory 同期テスト:"
echo "     bash $SCRIPT_DIR/sync-managed-memory.sh pull"
echo ""
echo "  2. cron-launcher.sh への Memory Sync 統合を確認:"
echo "     grep 'managed-memory' /home/kensan/Projects/*/Claude/templates/linux/cron-launcher.sh"
echo ""
echo "  3. セッション手動実行テスト:"
echo "     python3 $SCRIPT_DIR/managed-session.py run --phase monitor"
