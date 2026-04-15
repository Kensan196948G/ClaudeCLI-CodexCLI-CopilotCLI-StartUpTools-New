# Frontier-Test ループ

ハーネス制約の定期再評価ループ。
「現行のカスタム Agent / Skill / Hook / Rule が新モデルでも本当に必要か」を
月次でベンチマーク実行して検証し、不要判定の項目を Issue 化する。

本ファイルは **呼び出された Claude への命令書** である。
月次スケジュール（毎月第 1 月曜 09:00 JST）または手動起動時に以下の
実行契約を処理し、副作用（Issue 起票 + state.json 更新）を完了してから戻ること。

---

## 位置づけ

| 項目 | 値 |
|---|---|
| 実行頻度 | 月次（毎月第 1 月曜 09:00 JST） |
| 手動起動 | `/loop frontier-test` または cron 登録 |
| 副作用 1 | ラベル `frontier-test-deprecation-candidate` の Issue 起票 |
| 副作用 2 | `state.json.frontier` ブロック更新 |
| 参照元 Issue | #109 |
| 関連ループ | `improve-loop.md`（Stop-Doing 点検の定期実行層） |
| 関連ファイル | `.claude/claudeos/frontier/benchmark-tasks.md` |

---

## 実行契約（呼び出された Claude はこの順で処理すること）

### Step 1: 実行条件の確認

```
Read("./state.json")
```

以下のいずれかに該当する場合 → **何もせず終了**:

- `state.json` が存在しない
- `state.json.frontier.last_test_date` が現在月と同じ（当月実行済み）
- `.claude/claudeos/frontier/benchmark-tasks.md` が存在しない

### Step 2: 対象項目の列挙

過去 30 日に追加または更新された Auto Repair / Validation / Fallback 項目を抽出:

```bash
git log --since=30.days.ago --name-only --pretty=format: | sort -u | grep -E "agents/|skills/|hooks/|rules/"
```

加えて `state.json.learning.usage_history` から以下を抽出:
- 過去 90 日間 `total_count = 0` の項目（未使用）
- 過去 90 日間 `total_count ≤ 2` の項目（低利用）

### Step 3: ベンチマーク実行

`.claude/claudeos/frontier/benchmark-tasks.md` に定義された 10 件の代表タスクを実行:

各タスクを **2 パターン** で実施:
- (a) 対象制約を **有効** にして実行（通常実行）
- (b) 対象制約を **無効** にして実行（skip 実行）

判定基準:

| 判定 | 条件 |
|---|---|
| 不要（削除候補） | (b) の成功率 ≥ (a) の成功率 × 0.95 |
| 必要（保持） | (b) の成功率 < (a) の成功率 × 0.95 |
| 不確定 | ベンチマーク実行不能（skip 実行が副作用を持つ等） |

### Step 4: 削除候補の Issue 起票

Step 3 で「不要」判定された各項目につき Issue を 1 件起票:

```
mcp__plugin_github_github__issue_write({
  "owner": "...",
  "repo": "...",
  "title": "chore(frontier): [削除候補] {項目名} — Frontier-Test で不要判定",
  "body": "## Frontier-Test 結果\n- 項目: {パス}\n- 有効時成功率: {N}%\n- 無効時成功率: {N}%\n- 判定: 不要\n\n## 削除前確認事項\n- ...",
  "labels": ["frontier-test-deprecation-candidate"]
})
```

Step 2 の低利用項目（total_count ≤ 2）も別途 Issue 化:

```
title: "chore(frontier): [低利用] {項目名} — 90日間呼び出し {N} 回"
labels: ["frontier-test-low-usage"]
```

### Step 5: state.json の更新

```json
{
  "frontier": {
    "last_test_date": "{ISO 8601 UTC}",
    "test_count": (既存値 + 1),
    "last_deprecation_candidates": ["{項目名}", ...],
    "last_low_usage_items": ["{項目名}", ...]
  }
}
```

---

## ベンチマークタスク仕様

`.claude/claudeos/frontier/benchmark-tasks.md` には以下の形式で 10 件を定義する:

```markdown
## Task 1: {タスク名}
- 対象制約: {Agent/Skill/Hook 名}
- 入力: {テスト入力}
- 期待出力: {成功の定義}
- skip 実行時の副作用リスク: {なし/低/高}
```

skip 実行時の副作用リスクが「高」の場合はベンチマーク除外（不確定扱い）。

---

## schedule / cron 登録

月次実行の cron 式:

```
1 9 * * 1
```

（毎週月曜 09:00 JST — 毎月第 1 月曜に限定する場合は `state.json.frontier.last_test_date` の月次チェックで制御）

手動起動:

```
/loop frontier-test
```

---

## state.json スキーマ（本ループが参照・更新するブロック）

```json
{
  "frontier": {
    "last_test_date": null,
    "test_count": 0,
    "last_deprecation_candidates": [],
    "last_low_usage_items": []
  }
}
```

---

## 多重実行防止

| レイヤー | 条件 | 効果 |
|---|---|---|
| 当月チェック | `last_test_date` が当月ならスキップ | 月に 1 回のみ実行 |
| benchmark 不在 | `benchmark-tasks.md` 未存在ならスキップ | 初期化前は no-op |
| state.json 不在 | ファイル無しならスキップ | 新規プロジェクトで no-op |

---

## 参考

- Issue #109（本ループの実装対象）
- Anthropic blog: [Harnessing Claude's Intelligence](https://claude.com/blog/harnessing-claudes-intelligence) 末尾「The frontier of Claude's intelligence is always changing」
- Issue #103（Stop-Doing 点検）/ Issue #108（Dead-Weight 検出）— 本ループはこれらの月次実行層
- `improve-loop.md` — 四半期 Stop-Doing 点検との連携
