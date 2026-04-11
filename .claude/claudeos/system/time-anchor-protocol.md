# Time Anchor Protocol v1.0

_ClaudeOS v7.4 時間管理の 3 層防御アーキテクチャと self-discipline layer の正式規約。_

---

## 背景

2026-04-11 の独立検証により、ClaudeOS v7.4 CLAUDE.md の「max_duration_minutes: 300」は
**ドキュメント上の規約にすぎず、runtime 実装が完全に不在** であることが判明した
（state.json 固定値、hook スタブ、閾値分岐コードなし）。この欠陥を補修するため、3 層防御を導入した:

| # | レイヤー | 実装 | 責務 |
|---|---|---|---|
| 1 | **External (harness)** | `.claude/claudeos/scripts/hooks/session-start.js` + `.claude/settings.json` の SessionStart 登録 | セッション開始時に `.claude/session-anchor.json` を自動打刻 |
| 2 | **Self-discipline (claude)** | 本プロトコル | 各ループ開始時に Claude が anchor を Read → elapsed 計算 → state 書き戻し |
| 3 | **External (cron)** | CronCreate one-shot `recurring: false` | 物理的強制割り込み（Claude の規律に一切依存しない） |

本ドキュメントは **レイヤー 2** を正式化する。レイヤー 1 と 3 は実装済だが、それらを活用するための
Claude 側のルーチンが無ければ 3 層防御は成立しないため、以下の手順を規約として定める。

## 追補: Layer 4 + Layer 5 (2026-04-11 拡張)

2026-04-11 の作業で、SessionEnd と PreToolUse の両端点にも防御層を追加した:

| # | レイヤー | 実装 | 責務 |
|---|---|---|---|
| 4 | **SessionEnd 永続化** | `session-end.js` + `evaluate-session.js` + settings.json 登録 | セッション終了時に summary / history / evaluation JSON を生成、state.json を最終化 |
| 5 | **PreToolUse deadline check** (opt-in) | `pretool-deadline-check.js` (未登録) | 全ツール呼び出し前に anchor から remaining を計算し、`<= 0` で exit 2 ブロック |

**合計 5 層防御** で 5 時間厳守を実現する。Layer 5 は opt-in で、リスク評価後に settings.json へ登録する。

---

## 1. セッション開始時のプロトコル

### 1.1 初期 anchor 確認

Claude は最初の応答で必ず次を実行する:

1. `.claude/session-anchor.json` の存在確認
2. 存在する場合:
   - `wall_clock_start` の値が `now - 6h` より新しいか確認
   - 古い場合は「前回セッションの残留」とみなし、anchor を上書きしない（継続判断は §4 参照）
3. 存在しない場合（SessionStart hook が動かない環境）:
   - Claude 自身が `wall_clock_start` を現在時刻で書き込む（案 2 フォールバック）
   - `source: "manual-bootstrap"` を明示する

### 1.2 state.json の整合化

`.claude/session-anchor.json` を読み込んだ後、`state.json.execution` を以下で初期化する:

```
state.execution.start_time            = anchor.wall_clock_start
state.execution.end_time              = anchor.wall_clock_deadline
state.execution.max_duration_minutes  = anchor.max_duration_minutes
state.execution.elapsed_minutes       = 0
state.execution.remaining_minutes     = 300
state.status.last_updated             = anchor.wall_clock_start
```

---

## 2. 各ループ開始時のプロトコル

Monitor / Development / Verify / Improvement 各ループの開始時、**最初のツール呼び出しより前に** 以下を実行する:

### 2.1 経過時間の計算

```
anchor        = Read(.claude/session-anchor.json)
now           = 現在時刻 (UTC or JST どちらでも一貫していればよい)
elapsed_ms    = now - parse(anchor.wall_clock_start)
elapsed_min   = floor(elapsed_ms / 60000)
remaining_min = anchor.max_duration_minutes - elapsed_min
```

### 2.2 state.json への書き戻し

```
state.execution.elapsed_minutes   = elapsed_min
state.execution.remaining_minutes = remaining_min
state.execution.phase             = <現在のフェーズ名>
state.execution.loop_number       = <現在のループ番号>
state.status.current_phase        = <現在のフェーズ名>
state.status.last_updated         = now の ISO8601 文字列
```

### 2.3 閾値判定と分岐

`remaining_min` に基づいて次のように分岐する:

| 残時間 | アクション |
|---|---|
| `> 30` | 通常運用。全フェーズ実行可 |
| `≤ 30` | Improvement スキップ |
| `≤ 20` | Codex rescue は調査のみ許可（修正は禁止） |
| `≤ 15` | Verify 最小実行のみ（test / lint のみ、build / security はスキップ可） |
| `≤ 10` | 終了準備開始。新規作業禁止、commit / push / PR のみ許可 |
| `≤ 5` | 即終了処理。state 保存と安全停止のみ |
| `≤ 0` | 強制終了。CronCreate one-shot が発火している前提 |

---

## 3. フェーズ終了時のプロトコル

各ループの終了時:

1. §2 の計算を再実行して state.json を更新
2. `completed_this_loop` を記録
3. README / GitHub Projects の更新判断に remaining_min を考慮

---

## 4. セッション再開時の判断

`wall_clock_start` が 5 時間以上前の場合（例: 前回セッションが途中で終了し、新しいセッションが始まった）:

- SessionStart hook が動作している環境: hook が自動で anchor を上書きする（外部レイヤー 1 が処理）
- hook 未動作の環境: Claude が `wall_clock_start` を現在時刻で上書きし、`source: "session-resume"` をマークする

**判定**: 5 時間を超えて継続作業するのは規約違反。常にリセットして新しい 5 時間枠で開始する。

---

## 5. 実装責務マトリクス

| 手順 | 責任レイヤー | 実装場所 |
|---|---|---|
| anchor ファイル作成 | 外部ハーネス or Claude fallback | `session-start.js` or 手動 Write |
| anchor ファイル読み込み | Claude | 本プロトコル §2.1 |
| elapsed 計算 | Claude | 本プロトコル §2.1 |
| state.json 書き戻し | Claude | 本プロトコル §2.2 |
| 閾値分岐 | Claude | 本プロトコル §2.3 |
| 物理強制終了 | CronCreate one-shot | セッション開始時に CTO が仕込む |
| 終了処理フロー | Claude | CLAUDE.md §15「5 時間到達時の必須処理」 |

---

## 6. 検証チェックリスト

セッション中、次の条件が成立していることを定期的に確認する:

- [ ] `.claude/session-anchor.json` が存在する
- [ ] `anchor.wall_clock_start` と `state.execution.start_time` が一致している
- [ ] `state.execution.elapsed_minutes + remaining_minutes == max_duration_minutes` が成立する
- [ ] `remaining_minutes ≤ 0` の状態で新規ツール呼び出しを行っていない
- [ ] CronCreate one-shot job が 1 件登録されており、firing time が `wall_clock_deadline` と一致する

検証に失敗した場合、原因を特定してから次のアクションに進む。

---

## 7. Edge cases

### 7.1 anchor ファイル欠損

Claude は以下を順に試みる:

1. state.json.execution.start_time を暫定 anchor として利用
2. 現在時刻を `wall_clock_start` として新規 anchor を作成（案 2 fallback）
3. CronCreate one-shot を再仕込み

### 7.2 state.json 破損

state.json 読み込みが失敗した場合:

1. anchor から execution ブロックのみ再構築
2. 他フィールドは空 dict で初期化
3. Warning ログを残し、次回 Memory save で復元を試みる

### 7.3 タイムゾーン不一致

`wall_clock_start` は JST+09:00 で保存されることを前提とする。UTC 読み込みが必要な場合は
Claude が parse 時にオフセット変換する。CronCreate は local time を使うため、
cron 式は JST 基準で生成する。

---

## 8. 本プロトコルの位置付け

- CLAUDE.md §14「時間管理」の **実装手順書**
- CLAUDE.md §15「5 時間到達時の必須処理」の **前提条件文書**
- Evaluation Methodology v1.0 §6 の「Challenge 合格強み」の生きた実例

本プロトコルが実行されない限り、3 層防御は 2 層（外部ハーネス + 外部 cron）で動作する。
Claude の self-discipline 層が抜けると、0 < remaining_min < 30 の段階で閾値分岐が機能せず、
「残り 5 分で Improvement に着手」のような判断ミスを起こしうる。

---

## 8. Layer 5 — PreToolUse Deadline Check (opt-in)

### 8.1 目的

Layer 2 (Claude self-discipline) と Layer 3 (cron one-shot) はそれぞれ限界を持つ:

- **Layer 2** は Claude が anchor を読まなかった場合に無効化される
- **Layer 3** は cron 発火タイミングが粗く (分単位)、かつ recurring ではないため外乱に弱い

両者の狭間を埋めるのが Layer 5。`.claude/claudeos/scripts/hooks/pretool-deadline-check.js` を
PreToolUse hook として登録すると、**すべてのツール呼び出し前** に anchor を読み elapsed を計算し、
`remaining_minutes <= 0` の場合に exit code 2 でツール実行をブロックする。

### 8.2 状態機械

| remaining | アクション | 出力 | exit |
|---|---|---|---|
| `> 5` | allow (silent) | なし | 0 |
| `1 ≤ 5` | allow + WARN | stderr 警告 | 0 |
| `≤ 0` | **BLOCK** | stderr ブロック理由 | **2** |
| anchor 欠損 / parse 失敗 / その他例外 | **fail-open** | stderr 理由 | 0 |

### 8.3 Fail-open 設計原則

Layer 5 は **hook のバグでユーザーセッションをブリック化しない** ことを最優先とする。
anchor が無い、JSON が壊れている、タイムゾーン計算でエラー — これら全てのケースで **exit 0**
(allow) を返す。`remaining <= 0` の明確な判定ができたときにのみ block する。

### 8.4 登録手順 (opt-in)

本 Layer は opt-in (既定無効)。有効化するには `.claude/settings.json` の `hooks` に追記:

```json
"PreToolUse": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "node \"${CLAUDE_PROJECT_DIR}/.claude/claudeos/scripts/hooks/pretool-deadline-check.js\""
      }
    ]
  }
]
```

登録前に **必ず** 以下を確認する:

1. `.claude/session-anchor.json` が現在時刻 ± 5h 以内の値であること
2. smoke test (本プロトコル §8.5) が 5 シナリオ全てで期待通り動作すること
3. 緊急時の無効化手順 — settings.json の PreToolUse ブロックを削除

### 8.5 Smoke test (5 シナリオ)

2026-04-11 に実施した検証手順:

```bash
TMP=$(mktemp -d); mkdir -p "$TMP/.claude"
HOOK=".claude/claudeos/scripts/hooks/pretool-deadline-check.js"

# 1. normal (remaining=240) → exit 0 silent
cat > "$TMP/.claude/session-anchor.json" <<EOF
{"wall_clock_start":"$(date -u -d '60 minutes ago' '+%Y-%m-%dT%H:%M:%S+00:00')","max_duration_minutes":300}
EOF
CLAUDE_PROJECT_DIR="$TMP" node "$HOOK" < /dev/null   # expect exit=0

# 2. warn (remaining=3)     → exit 0 with stderr WARN
# 3. block (remaining=-10)  → exit 2 with stderr BLOCK
# 4. no anchor              → exit 0 fail-open
# 5. invalid JSON           → exit 0 fail-open
```

全 5 scenarios で期待通り動作することを local で確認済 (runtime-verified)。

## Revision History

| version | date | change |
|---|---|---|
| v1.0 | 2026-04-11 | 初版。5h Sign-Flip Incident を受けてレイヤー 2 を正式化 |
| v1.1 | 2026-04-11 | Layer 4 (SessionEnd hooks) + Layer 5 (PreToolUse, opt-in) を追補 |
