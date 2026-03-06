# Statusline グローバル再設定 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `scripts/statusline.sh` を3行フォーマット（モデル/コンテキスト/編集量/ブランチ + 5h/7dレート制限）に全面改訂し、既存のbase64転送機構でグローバルとプロジェクト両方に自動展開する。

**Architecture:** PowerShell側（`Claude-DevTools.ps1`）は変更不要。`scripts/statusline.sh` のみ改訂する。スクリプトはbase64エンコードでSSH転送され `~/.claude/statusline.sh` と `.claude/statusline.sh` に展開される。グローバル `settings.json` への `statusLine.command` 書き込みは `Claude-DevTools.ps1:438` が既に処理済み。Haiku Probeでレート制限ヘッダーを取得し6分キャッシュに保存する。

**Tech Stack:** bash, curl (Haiku Probe), jq (JSON parse), date (TZ=Asia/Tokyo), Unicode block chars (▰▱), stat (cache TTL)

---

## 表示フォーマット（承認済み）

```
🤖 Opus 4.6 │ 📊 25% │ ✏️  +5/-1 │ 🔀 main
⏱ 5h  ▰▰▰▱▱▱▱▱▱▱  28%  Resets 9pm (Asia/Tokyo)
📅 7d  ▰▰▰▰▰▰▱▱▱▱  59%  Resets Mar 6 at 1pm (Asia/Tokyo)
```

---

### Task 1: テストスクリプト作成

**Files:**
- Create: `tests/test-statusline-v2.sh`

**Step 1: テストスクリプトを作成する**

```bash
#!/usr/bin/env bash
# tests/test-statusline-v2.sh — statusline.sh v2 フォーマット検証テスト
set -uo pipefail

PASS=0
FAIL=0
SCRIPT="scripts/statusline.sh"

assert_contains() {
    local name="$1" output="$2" expected="$3"
    if echo "$output" | grep -qF "$expected"; then
        echo "✓ $name"
        ((PASS++))
    else
        echo "✗ $name"
        echo "  期待: $expected"
        echo "  実際: $output"
        ((FAIL++))
    fi
}

assert_not_contains() {
    local name="$1" output="$2" unexpected="$3"
    if ! echo "$output" | grep -qF "$unexpected"; then
        echo "✓ $name"
        ((PASS++))
    else
        echo "✗ $name (含まれてはいけない: $unexpected)"
        ((FAIL++))
    fi
}

MOCK_JSON='{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":25},"session":{"lines_added":5,"lines_removed":1},"workspace":{"current_dir":"."}}'

echo "=== Test Suite: statusline.sh v2 ==="
echo ""

# --- テスト1: Line 1 モデル名表示 ---
echo "--- Line 1 Tests ---"
LINE1=$(echo "$MOCK_JSON" | bash "$SCRIPT" | head -1)
assert_contains "Line1: 🤖 が含まれる" "$LINE1" "🤖"
assert_contains "Line1: Opus 4.6 (Claude省略)" "$LINE1" "Opus 4.6"
assert_not_contains "Line1: 'Claude' が省略される" "$LINE1" "Claude Opus"
assert_contains "Line1: 📊 が含まれる" "$LINE1" "📊"
assert_contains "Line1: 25% が含まれる" "$LINE1" "25%"
assert_contains "Line1: ✏️ が含まれる" "$LINE1" "✏️"
assert_contains "Line1: +5/-1 が含まれる" "$LINE1" "+5/-1"
assert_contains "Line1: │ 区切り文字" "$LINE1" "│"

# --- テスト2: Line 1 Git ブランチ（gitリポジトリ内） ---
echo ""
echo "--- Git Branch Tests ---"
GIT_DIR_JSON="{\"model\":{\"display_name\":\"Claude Sonnet 4.6\"},\"context_window\":{\"used_percentage\":0},\"session\":{},\"workspace\":{\"current_dir\":\"$(pwd)\"}}"
LINE1_GIT=$(echo "$GIT_DIR_JSON" | bash "$SCRIPT" | head -1)
assert_contains "Line1: 🔀 Gitブランチ表示" "$LINE1_GIT" "🔀"

# --- テスト3: APIキーなしの場合1行のみ出力 ---
echo ""
echo "--- No API Key Tests ---"
OUTPUT_NO_API=$(ANTHROPIC_API_KEY="" echo "$MOCK_JSON" | bash "$SCRIPT" 2>/dev/null)
LINE_COUNT=$(echo "$OUTPUT_NO_API" | grep -c .)
assert_contains "APIキーなし: 出力行数=1" "$LINE_COUNT" "1"

# --- テスト4: 空入力でもエラーにならない ---
echo ""
echo "--- Empty Input Tests ---"
OUTPUT_EMPTY=$(ANTHROPIC_API_KEY="" echo "" | bash "$SCRIPT" 2>/dev/null || true)
assert_contains "空入力: エラーなし(🤖含む)" "$OUTPUT_EMPTY" "🤖"

# --- テスト5: コンテキスト100%でも動作 ---
echo ""
echo "--- Edge Case Tests ---"
EDGE_JSON='{"model":{"display_name":"Unknown"},"context_window":{"used_percentage":100},"session":{},"workspace":{"current_dir":"."}}'
LINE1_EDGE=$(ANTHROPIC_API_KEY="" echo "$EDGE_JSON" | bash "$SCRIPT" | head -1)
assert_contains "100%コンテキスト: 正常出力" "$LINE1_EDGE" "100%"

# --- テスト6: プログレスバー文字列（API利用時） ---
echo ""
echo "--- Progress Bar Format (requires API) ---"
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    OUTPUT_WITH_API=$(echo "$MOCK_JSON" | bash "$SCRIPT" 2>/dev/null)
    LINES=$(echo "$OUTPUT_WITH_API" | wc -l)
    assert_contains "APIキーあり: 3行出力" "$LINES" "3"
    LINE2=$(echo "$OUTPUT_WITH_API" | sed -n '2p')
    LINE3=$(echo "$OUTPUT_WITH_API" | sed -n '3p')
    assert_contains "Line2: ⏱ が含まれる" "$LINE2" "⏱"
    assert_contains "Line2: 5h が含まれる" "$LINE2" "5h"
    assert_contains "Line2: プログレスバー文字▰か▱" "$LINE2" "▰"
    assert_contains "Line2: Resets が含まれる" "$LINE2" "Resets"
    assert_contains "Line3: 📅 が含まれる" "$LINE3" "📅"
    assert_contains "Line3: 7d が含まれる" "$LINE3" "7d"
    assert_contains "Line3: Asia/Tokyo が含まれる" "$LINE3" "Asia/Tokyo"
else
    echo "ℹ ANTHROPIC_API_KEY 未設定 — APIテストをスキップ"
fi

echo ""
echo "================================="
echo "Results: $PASS passed, $FAIL failed"
echo "================================="
[ "$FAIL" -eq 0 ]
```

**Step 2: テストを実行して失敗を確認する**

```bash
cd D:\Claude-EdgeChromeDevTools  # Git Bash: /d/Claude-EdgeChromeDevTools
bash tests/test-statusline-v2.sh
```

期待される結果: `Line1: Opus 4.6 (Claude省略)` で **FAIL**（現在の statusline.sh は古いフォーマット）

**Step 3: コミット（テストスクリプトのみ）**

```bash
git add tests/test-statusline-v2.sh
git commit -m "test: statusline v2フォーマット検証テストスクリプト追加"
```

---

### Task 2: statusline.sh 全面改訂

**Files:**
- Modify: `scripts/statusline.sh` (127行 → 全面置換)

**Step 1: 新しい statusline.sh を実装する**

`scripts/statusline.sh` を以下の内容に完全置換する:

```bash
#!/usr/bin/env bash
# Claude Code Statusline v2
# Format:
#   🤖 Opus 4.6 │ 📊 25% │ ✏️  +5/-1 │ 🔀 main
#   ⏱ 5h  ▰▰▰▱▱▱▱▱▱▱  28%  Resets 9pm (Asia/Tokyo)
#   📅 7d  ▰▰▰▰▰▰▱▱▱▱  59%  Resets Mar 6 at 1pm (Asia/Tokyo)
set -euo pipefail

# === 入力受付 ===
input="$(cat)"
if [ -z "$input" ]; then
    input="{\"model\":{\"display_name\":\"Unknown\"},\"workspace\":{\"current_dir\":\"$(pwd)\"},\"context_window\":{\"used_percentage\":0},\"session\":{}}"
fi

# === Line 1 パース ===
MODEL_FULL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
MODEL_SHORT="${MODEL_FULL#Claude }"  # "Claude Opus 4.6" → "Opus 4.6"

USED_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
USED_PCT=$(printf '%.0f' "${USED_PCT:-0}" 2>/dev/null || echo 0)

LINES_ADDED=$(echo "$input" | jq -r '.session.lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.session.lines_removed // 0')

DIR=$(echo "$input" | jq -r '.workspace.current_dir // "."')
DIR="${DIR:-.}"

# Git ブランチ
GIT_BRANCH=""
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null || true)
    if [ -z "$GIT_BRANCH" ]; then
        GIT_BRANCH=$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null || true)
    fi
fi
BRANCH_SEG=""
[ -n "$GIT_BRANCH" ] && BRANCH_SEG=" │ 🔀 $GIT_BRANCH"

# === Line 1 出力 ===
echo "🤖 ${MODEL_SHORT} │ 📊 ${USED_PCT}% │ ✏️  +${LINES_ADDED}/-${LINES_REMOVED}${BRANCH_SEG}"

# === ユーティリティ関数 ===

# 10段階プログレスバー (▰=使用済み ▱=残り)
make_bar() {
    local pct="${1:-0}"
    local filled=$(( pct * 10 / 100 ))
    local bar="" i=0
    while [ $i -lt $filled ]; do bar="${bar}▰"; ((i++)) || true; done
    while [ $i -lt 10 ];     do bar="${bar}▱"; ((i++)) || true; done
    echo "$bar"
}

# リセット時刻フォーマット: ISO8601 → "Resets 9pm (Asia/Tokyo)" / "Resets Mar 6 at 1pm (Asia/Tokyo)"
format_reset() {
    local reset_utc="$1"
    [ -z "$reset_utc" ] && { echo "Resets ? (Asia/Tokyo)"; return; }

    local now_day reset_day
    now_day=$(TZ=Asia/Tokyo date +"%Y-%m-%d" 2>/dev/null) || { echo "Resets ? (Asia/Tokyo)"; return; }
    reset_day=$(TZ=Asia/Tokyo date -d "$reset_utc" +"%Y-%m-%d" 2>/dev/null) || { echo "Resets ? (Asia/Tokyo)"; return; }

    local hour_str
    if [ "$now_day" = "$reset_day" ]; then
        hour_str=$(TZ=Asia/Tokyo date -d "$reset_utc" +"%-I%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        echo "Resets ${hour_str} (Asia/Tokyo)"
    else
        local month_day
        month_day=$(TZ=Asia/Tokyo date -d "$reset_utc" +"%b %-d at %-I%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        # 先頭文字だけ大文字: "mar 6 at 1pm" → "Mar 6 at 1pm"
        echo "Resets $(echo "${month_day:0:1}" | tr '[:lower:]' '[:upper:]')${month_day:1} (Asia/Tokyo)"
    fi
}

# === Haiku Probe (レート制限取得) ===
CACHE_FILE="/tmp/.claude-statusline-cache"
CACHE_TTL=360  # 6分

RATE_HEADERS=""

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    : # APIキー未設定 → Line 2/3 をスキップ
elif [ -f "$CACHE_FILE" ]; then
    cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    cache_age=$(( $(date +%s) - cache_mtime ))
    if [ "$cache_age" -lt "$CACHE_TTL" ]; then
        RATE_HEADERS=$(cat "$CACHE_FILE")
    fi
fi

# キャッシュなし or 期限切れ → Haiku Probe
if [ -z "$RATE_HEADERS" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    RATE_HEADERS=$(curl -s -I -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        2>/dev/null | tr -d '\r') || RATE_HEADERS=""
    [ -n "$RATE_HEADERS" ] && echo "$RATE_HEADERS" > "$CACHE_FILE" || true
fi

# === Line 2/3 出力 (APIキーあり + レート制限取得成功時) ===
if [ -n "$RATE_HEADERS" ]; then
    # requests ヘッダー抽出
    REQ_REMAINING=$(echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-requests-remaining:' | awk '{print $2}' | head -1 | tr -d '[:space:]')
    REQ_LIMIT=$(    echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-requests-limit:'     | awk '{print $2}' | head -1 | tr -d '[:space:]')
    REQ_RESET=$(    echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-requests-reset:'     | awk '{print $2}' | head -1 | tr -d '[:space:]')

    # tokens ヘッダー抽出
    TOK_REMAINING=$(echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-tokens-remaining:' | awk '{print $2}' | head -1 | tr -d '[:space:]')
    TOK_LIMIT=$(    echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-tokens-limit:'     | awk '{print $2}' | head -1 | tr -d '[:space:]')
    TOK_RESET=$(    echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-tokens-reset:'     | awk '{print $2}' | head -1 | tr -d '[:space:]')

    # パーセンテージ計算 (使用率 = (limit - remaining) / limit * 100)
    REQ_PCT=0
    if [ -n "$REQ_LIMIT" ] && [ "${REQ_LIMIT:-0}" -gt 0 ] 2>/dev/null; then
        REQ_USED=$(( REQ_LIMIT - ${REQ_REMAINING:-0} ))
        REQ_PCT=$(( REQ_USED * 100 / REQ_LIMIT ))
    fi

    TOK_PCT=0
    if [ -n "$TOK_LIMIT" ] && [ "${TOK_LIMIT:-0}" -gt 0 ] 2>/dev/null; then
        TOK_USED=$(( TOK_LIMIT - ${TOK_REMAINING:-0} ))
        TOK_PCT=$(( TOK_USED * 100 / TOK_LIMIT ))
    fi

    REQ_BAR=$(make_bar "$REQ_PCT")
    TOK_BAR=$(make_bar "$TOK_PCT")
    REQ_RESET_STR=$(format_reset "$REQ_RESET")
    TOK_RESET_STR=$(format_reset "$TOK_RESET")

    # Line 2: requests ウィンドウ (⏱ 5h)
    echo "⏱ 5h  ${REQ_BAR}  ${REQ_PCT}%  ${REQ_RESET_STR}"

    # Line 3: tokens ウィンドウ (📅 7d)
    echo "📅 7d  ${TOK_BAR}  ${TOK_PCT}%  ${TOK_RESET_STR}"
fi
```

**Step 2: テストを実行してパスを確認する（APIキーなし部分のみ）**

```bash
bash tests/test-statusline-v2.sh
```

期待される結果: `APIキーなし` テスト群がすべて **PASS**、APIテストは `スキップ` と表示される

**Step 3: 手動動作確認（モック入力）**

```bash
echo '{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":25},"session":{"lines_added":5,"lines_removed":1},"workspace":{"current_dir":"."}}' | bash scripts/statusline.sh
```

期待される出力（Line 1のみ、APIキーなし）:
```
🤖 Opus 4.6 │ 📊 25% │ ✏️  +5/-1 │ 🔀 main
```

**Step 4: コミット**

```bash
git add scripts/statusline.sh
git commit -m "feat: statusline v2 — Haiku Probe方式 5h/7dレート制限表示・GitHub参照フォーマット実装"
```

---

### Task 3: フルフロー検証（Linux側での実地テスト）

> ⚠️ このTaskはLinux側で実行する。Windowsからの確認手順。

**Files:**
- 変更なし（既存のSSH転送機構を利用）

**Step 1: `Claude-DevTools.ps1` を起動して転送を確認する**

1. `start.bat` からブラウザ選択 → Claude Code 起動
2. 起動ログで以下を確認:
   ```
   ✅ Statusline スクリプトを配置しました
   ✅ グローバル設定をマージ更新しました
   ```

**Step 2: Linux側で statusline.sh が更新されたか確認する**

```bash
# Linux側 SSH セッションで確認
head -5 ~/.claude/statusline.sh
# 期待: #!/usr/bin/env bash と "Claude Code Statusline v2" コメント
```

**Step 3: Linux側で手動テスト実行**

```bash
cd ~/.claude
bash tests/test-statusline-v2.sh  # プロジェクトにテストがある場合

# または手動確認
echo '{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":30},"session":{"lines_added":2,"lines_removed":0},"workspace":{"current_dir":"/home/kensan"}}' | bash ~/.claude/statusline.sh
```

**Step 4: ANTHROPIC_API_KEY 設定済みで全3行確認**

```bash
# ANTHROPIC_API_KEY が設定されていること前提
echo '{"model":{"display_name":"Claude Sonnet 4.6"},"context_window":{"used_percentage":45},"session":{},"workspace":{"current_dir":"."}}' | ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" bash ~/.claude/statusline.sh
```

期待される全3行出力:
```
🤖 Sonnet 4.6 │ 📊 45% │ ✏️  +0/-0 │ 🔀 main
⏱ 5h  ▰▰▰▰▱▱▱▱▱▱  40%  Resets 9pm (Asia/Tokyo)
📅 7d  ▰▰▰▰▰▰▰▱▱▱  70%  Resets Mar 6 at 1pm (Asia/Tokyo)
```

**Step 5: Claude Code 内の statusline 表示を確認**

Claude Code セッション内で `/statusline` コマンドを実行してステータスラインが3行で表示されることを確認する。

---

### Task 4: PR作成

**Files:**
- 変更なし

**Step 1: ブランチ・コミット確認**

```bash
git log --oneline -5
git status
```

**Step 2: PR作成**

```bash
gh pr create \
  --title "feat: Statusline v2 — GitHub参照フォーマット + Haiku Probe 5h/7dレート制限表示" \
  --body "$(cat <<'EOF'
## Summary
- `scripts/statusline.sh` を3行フォーマットに全面改訂
- Line 1: `🤖 Model │ 📊 Context% │ ✏️  +X/-Y │ 🔀 branch`
- Line 2: `⏱ 5h ▰▰▰▱▱▱▱▱▱▱ X% Resets Hpm (Asia/Tokyo)` (requests rate limit)
- Line 3: `📅 7d ▰▰▰▰▰▰▱▱▱▱ X% Resets Mar D at Hpm (Asia/Tokyo)` (tokens rate limit)
- Haiku Probe方式: `ANTHROPIC_API_KEY` 使用、6分キャッシュ (`/tmp/.claude-statusline-cache`)
- PowerShell側変更なし（既存のbase64転送 + グローバルsettings.json更新機構を活用）

## Test plan
- [ ] `bash tests/test-statusline-v2.sh` がすべてPASS
- [ ] モック入力でLine 1フォーマットを手動確認
- [ ] Linux側での `bash ~/.claude/statusline.sh` 動作確認
- [ ] ANTHROPIC_API_KEY設定時の全3行表示確認
- [ ] Claude Code 内での `/statusline` 表示確認

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 制約・注意事項

- `set -euo pipefail` — `((i++))` は i=0 の場合に exit code 1 を返す → `|| true` で回避
- `stat -c %Y` はLinux専用（macOS は `stat -f %m`） — 本実装はLinux専用のため問題なし
- `date -d` はLinux GNU date専用 — macOS非対応（設計通り）
- `%-I` フォーマット（ゼロパディングなし時刻）もLinux GNU date専用
- Haiku Probe のコスト: 約 $0.000025/回（6分に1回上限）
- `ANTHROPIC_API_KEY` 未設定時は Line 2/3 を静かにスキップ（エラーなし）
- キャッシュファイル `/tmp/.claude-statusline-cache` は再起動で消える（意図通り）
