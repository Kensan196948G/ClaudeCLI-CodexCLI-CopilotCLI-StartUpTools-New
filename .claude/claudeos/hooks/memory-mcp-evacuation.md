# memory-mcp-evacuation

PreCompact フックとして起動するセッション状態 Memory MCP 退避器。
`/compact` 実行直前に `state.json` の重要フィールドを Memory MCP へエンティティとして書き込み、
コンパクション後も作業継続性を維持する。

本ファイルは静的なドキュメントではなく、**呼び出された Claude への命令書** である。
Claude Code の hook システムがこのフックを起動したとき、以下の実行契約を順に処理し、
副作用（Memory MCP への書き込み + `state.json` タイムスタンプ更新）を完了してから戻ること。

---

## 位置づけ

| 項目 | 値 |
|---|---|
| フック種別 | PreCompact |
| 対象イベント | `/compact` 実行前 |
| 副作用 1 | Memory MCP エンティティへのセッション状態書き込み |
| 副作用 2 | `.claude/claudeos/snapshots/evacuation-latest.json` の更新（pre-compact.js が担当） |
| 副作用 3 | `state.json.compact.last_pre_compact_at` 更新（pre-compact.js が担当） |
| 参照元 Issue | #176 |
| 関連スクリプト | `.claude/claudeos/scripts/hooks/pre-compact.js`（同フェーズの Node.js 側） |

---

## 実行契約（呼び出された Claude はこの順で処理すること）

### Step 1: Memory MCP 接続確認

`mcp__memory__read_graph` または `mcp__memory__search_nodes` を呼び出し、
Memory MCP が応答するか確認する。

- 呼び出しが失敗する（エラー / タイムアウト）→ **no-op で終了**（セッションを止めない）
- 呼び出しが成功する → Step 2 へ進む

### Step 2: state.json の読み取り

```
Read("./state.json")
```

以下のいずれかに該当する場合 → **何もせず終了**:

- `state.json` が存在しない
- `execution` ブロックが欠損

### Step 3: 退避エンティティの構築

以下のフィールドを `state.json` から収集し、退避エンティティを構築する:

| フィールド | パス | 用途 |
|---|---|---|
| フェーズ | `execution.phase` | 再開時の作業位置 |
| セッション要約 | `execution.last_session_summary` | 前回作業内容 |
| STABLE 状態 | `stable.stable_achieved` / `stable.consecutive_success` | 品質状態 |
| 最終検証日時 | `stable.last_verified_at` | STABLE の鮮度 |
| 停止日時 | `execution.last_stop_at` | セッション境界 |
| 現在フェーズ予算 | `token.current_phase_used` | トークン消費状況 |

### Step 4: Memory MCP への書き込み

`mcp__memory__create_entities` または `mcp__memory__add_observations` を使い、
以下のエンティティを書き込む:

```json
{
  "entities": [
    {
      "name": "ClaudeOS_SessionState_<ISO8601日時>",
      "entityType": "SessionEvacuation",
      "observations": [
        "phase: <execution.phase>",
        "summary: <execution.last_session_summary>",
        "stable: <stable.stable_achieved> (consecutive=<consecutive_success>)",
        "last_verified_at: <stable.last_verified_at>",
        "evacuated_at: <現在時刻 ISO 8601>"
      ]
    }
  ]
}
```

- エンティティ名は衝突回避のため ISO 8601 タイムスタンプをサフィックスに付ける
- 書き込み失敗時はログを出力して継続（セッションを止めない）

### Step 5: 古い退避エンティティの整理

`mcp__memory__search_nodes` で `"SessionEvacuation"` 型のエンティティを検索し、
最新 5 件を超える古いエントリは `mcp__memory__delete_entities` で削除する。

- 削除失敗は無視して継続

### Step 6: 完了ログ

コンソールに以下を出力して終了:

```
[memory-mcp-evacuation] session state evacuated to Memory MCP at <ISO 8601>
```

---

## 多重実行防止

| 条件 | 対応 |
|---|---|
| Memory MCP 未接続 | Step 1 で no-op 終了 |
| state.json 不在 | Step 2 で no-op 終了 |
| /compact 連続実行 | エンティティ名にタイムスタンプ → 既存と衝突しない |

---

## state.json スキーマ（本フックが参照するブロック）

```json
{
  "execution": {
    "phase": "Monitor",
    "last_session_summary": "...",
    "last_stop_at": null
  },
  "stable": {
    "consecutive_success": 0,
    "stable_achieved": false,
    "last_verified_at": null
  },
  "compact": {
    "last_pre_compact_at": null
  },
  "token": {
    "current_phase_used": 0
  }
}
```

---

## 受入れ基準との対応

Issue #176 の受入れ基準との対応:

| 受入れ基準 | 本フックでの対応箇所 |
|---|---|
| `memory-mcp-evacuation.md` が存在する | 本ファイル |
| `hooks.json` の `PreCompact` に登録されている | `.claude/claudeos/hooks/hooks.json` |
| Memory MCP 未接続環境で no-op 終了 | Step 1 |
| セッション状態が Memory MCP へ保存される | Step 4 |
| 古い退避エンティティが整理される | Step 5 |

---

## 参考

- Issue #176（本フックの実装対象）
- `.claude/claudeos/scripts/hooks/pre-compact.js`（同フェーズの Node.js スクリプト — evacuation-latest.json を書き出す）
- `.claude/claudeos/hooks/onboarding-refresh-on-stable.md`（同パターンの PostToolUse フック先行実装）
- `CLAUDE.md` §5 運用ループ / §19 自動停止条件
