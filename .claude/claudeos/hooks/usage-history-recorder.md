# usage-history-recorder

PostToolUse の通常フックとして起動する使用履歴記録器。
Agent / Skill / Command / Task ツールの呼び出し後に、対象項目を
`state.json.learning.usage_history` に記録する。

本ファイルは静的なドキュメントではなく、**呼び出された Claude への命令書** である。
Claude Code の hook システムがこのフックを起動したとき、以下の実行契約を順に処理し、
副作用（state.json 更新）を完了してから戻ること。

---

## 位置づけ

| 項目 | 値 |
|---|---|
| フック種別 | PostToolUse |
| 対象ツール | `Agent` / `Skill` / `Task`（matcher: `Agent\|Skill\|Task`） |
| 対象外 | `Bash` / `Read` / `Glob` / `Grep` / `Edit` / `Write`（汎用ツール、個別記録の意味が薄い） |
| 副作用 | `state.json.learning.usage_history` の更新（唯一の書き込み箇所） |
| 参照元 Issue | #108 |
| 関連フック | `capture-result`（先に動作、無干渉） |
| データ消費側 | `.claude/claudeos/loops/improve-loop.md` の Dead-Weight 検出セクション |

---

## 実行契約（呼び出された Claude はこの順で処理すること）

### Step 1: 対象ツール判定

入力の `tool_name` を確認する。

- `Agent`: `subagent_type` を項目名として抽出（例: `feature-dev:code-architect`）
- `Skill`: `skill` パラメータを項目名として抽出（例: `loop`, `commit`）
- `Task`: `description` または `prompt` 先頭 50 文字を項目名として抽出（生成物からの抽出）
- それ以外: 記録対象外、即座に終了

### Step 2: state.json の読み取り

```
Read("./state.json")
```

- state.json が存在しない → **何もせず終了**（新規プロジェクトで誤作動しない）
- `learning.usage_history` ブロックが欠損 → 空オブジェクトを想定して後続処理（初回書き込み）

### Step 3: 該当カテゴリのエントリ更新

項目名と現在時刻（ISO 8601 UTC）を使って、以下のロジックで更新:

```
category = Step 1 で判定したカテゴリ（agents / skills / commands / hooks）
name = Step 1 で抽出した項目名

if usage_history[category][name] が存在:
  usage_history[category][name].last_invoked = now
  usage_history[category][name].total_count += 1
else:
  usage_history[category][name] = {
    "last_invoked": now,
    "total_count": 1,
    "seasonal": false,
    "first_invoked": now
  }
```

### Step 4: state.json の書き戻し

```
Write("./state.json", 更新後の JSON 文字列)
```

書き戻し前に以下を検証:
- JSON として valid か（parse エラーなら abort）
- `learning.usage_history` 以外のブロックが破壊されていないか（diff 確認）

### Step 5: 書き戻し失敗時の挙動

- 書き込みエラー → 標準エラーにログ出力のみ（セッション継続）
- 連続 3 回失敗 → state.json が破損している可能性、フックを一時無効化する旨を警告

---

## 猶予期間と seasonal フラグ

### 猶予期間（grace period）

新規項目は初回記録時に `first_invoked = now` が付与される。Dead-Weight 検出側は
`state.json.learning.dead_weight.grace_period_days`（既定 30 日）以内の項目を
検出対象から除外する。本フックは記録のみを担当し、grace period の判定はしない。

### seasonal フラグ

項目のフロントマター（Agent / Skill / Command の `.md` ファイル先頭）に
`seasonal: true` が明示されている場合、本フックは `usage_history` 更新時に
`seasonal: true` を付与する。Dead-Weight 検出側はこのフラグが立った項目を
常に対象外とする（期間限定タスク用のため）。

---

## レート制限

PostToolUse フックは頻繁に発火するため、過剰な state.json 書き込みを避ける:

- 直近 10 秒以内に同一項目を記録した場合、`total_count` のみ加算し `last_invoked`
  は更新しない（書き込み衝突回避）
- セッション終了時（Stop フック）に集計した差分をまとめて書き込む方針も選択肢
  （将来の最適化候補、本フック初版ではシンプルに即時書き込み）

---

## 想定される誤作動と対策

| 誤作動 | 対策 |
|---|---|
| state.json が他プロセスと競合 | Write 前に `Read` で最新を取得し merge |
| 項目名に特殊文字（JSON キーとして不正） | `name.replace(/[^\w\-:]/g, "_")` で sanitize |
| total_count が整数オーバーフロー | JS Number として 2^53 未満に収まる想定、現実的には問題なし |
| frontmatter の `seasonal` 読み取り失敗 | デフォルト false として扱う |

---

## 参考

- Issue #108（本フックの実装対象）
- Issue #103（Stop-Doing 点検 — 本フックが記録したデータを利用する側）
- `.claude/claudeos/loops/improve-loop.md` の Dead-Weight Detection セクション
- Anthropic ブログ: [Harnessing Claude's Intelligence](https://claude.com/blog/harnessing-claudes-intelligence) パターン 2 "Ask what you can stop doing"
