# Role Contracts (Reference)

このファイルは ClaudeOS における **Orchestrator-Subagent パターンの参考資料** である。
Anthropic の multi-agent coordination 原則の適用例を示し、将来の段階的な改善の起点となることを意図する。

## 🎯 本ファイルの性格 (重要)

- **リファレンス** である。他ファイルに対する強制ソースではない
- **既存ファイルを書き換えない**: `system/orchestrator.md`, `system/loop-guard.md`, `loops/*-loop.md`, `CLAUDE.md`, `state.schema.json` などの既存定義と **共存する**
- ここに書かれたパターンは「将来採用できる選択肢」であり、既存運用の即時変更を要求しない
- 実際の運用規約 (5 時間ルール、停止条件、CI 修復、Codex 統合、state.json スキーマ) は既存の `system/`, `loops/`, `CLAUDE.md`, `docs/common/schemas/` が真実のソースである

## 第一原則 (Anthropic multi-agent coordination)

> **最も単純に動く形から始め、詰まった地点でのみ複雑化する。**

Message Bus / Shared State / Event-driven などの高度な協調パターンは、
必要に迫られた時にのみ段階導入する。既定は **Orchestrator-Subagent** の単一パターン。

## Orchestrator-Subagent パターン (推奨パターン)

```
Orchestrator
  ├─ Subagent A (担当ファイル境界: X)
  ├─ Subagent B (担当ファイル境界: Y)
  └─ Subagent C (担当ファイル境界: Z)
       ↑ 各 Subagent は Orchestrator に構造化された結果を返す
```

- Orchestrator は分解と統制に専念し、自分ではコード編集しない
- Subagent は担当範囲内のみで作業し、互いに干渉しない
- 返却は後述の 4 セクション形式で構造化する

## Light / Full モード (推奨)

新タスク受領時、Orchestrator は **最初にモードを宣言する** ことを推奨する:

| モード | 想定されるタスク |
|---|---|
| **light** (既定) | 1 ファイル修正 / lint / doc / 軽微なバグ修正 / 差分 < 50 行 |
| **full** | 新機能 / 認証・権限・DB スキーマ変更 / 並列同期 / 差分 ≥ 50 行 or 3 ファイル以上 |

- 既定は light
- light で足りるなら full に昇格しない
- full への昇格は Orchestrator が理由を明示する

この判定は**強制ではなく推奨**である。既存の運用フローと競合しない範囲で採用できる。

## 返却フォーマット (推奨: 4 セクション固定)

サブエージェントの返却を以下の 4 セクション固定にすると、Orchestrator の検証が機械化しやすい:

```markdown
## Summary
- 1〜3 行の結論 (最も重要なリスクから書き始める。賞賛から始めない)

## Risks
- 未確認点・前提破れ・副作用候補
- 重大度 (high / medium / low) を付与する
- 空なら "none"

## Findings
- 観測事実のみ (根拠ファイル:行番号を添える)

## Next Action
- Orchestrator が次に踏むべき 1 手 (候補 1〜3)
```

順序は **Summary → Risks → Findings → Next Action** 固定。
Risks を Findings より前に配置するのは、重要な論点が埋もれないようにするため。

## ロール設計の一般パターン (参考)

各サブエージェントを定義する際は、以下を明記することが推奨される:

- **入力**: 何を受け取るか
- **出力**: 4 セクション形式で何を返すか
- **完了条件**: 何をもって終了とするか
- **禁止事項**: 何をしてはいけないか
- **参照許可**: どのファイルを読み書きしてよいか

具体的なロール定義 (Developer / Reviewer / QA / Security / ...) は、本ファイルでは強制せず、プロジェクトごとに実装の必要に応じて追加する。

## 並列実行のパターン (参考)

複数のサブエージェントを並列実行する場合の推奨パターン:

1. **担当ファイル境界を事前宣言する** — エージェントごとに排他的に割り当てる
2. **共有ファイルの writer は 1 人に限定する** — README.md / 設定ファイルなど
3. **終了条件を 3 系統で定義する** — `時間 (max duration)` / `収束 (no-change N 回)` / `担当判定 (Orchestrator の強制終了)`

これらは並列の競合を避けるためのパターンであり、強制ではない。

## Codex Plugin の基本パターン (参考)

| コマンド | 用途 |
|---|---|
| `exec` | 新規実装・修正を Codex に委ねる |
| `review` | 差分レビュー |
| `adversarial-review` | 対抗レビュー (認証・権限・DB・並列・リリース直前) |
| `rescue` | 原因調査・最小修正案 (1 rescue = 1 仮説) |
| `resume` | 中断中の job 再開 |
| `fork` | 並列な別仮説を試す |

詳細な使い分けは `AGENTS.md` を参照。

## 今後の段階導入 (ロードマップ)

本ファイルの内容を段階的に運用へ反映する場合、以下の順序が推奨される:

1. **Phase 1** — 返却フォーマット 4 セクションの採用 (ツールと文書の両方で試す)
2. **Phase 2** — light / full モード判定の試験的導入 (Orchestrator が宣言するだけ)
3. **Phase 3** — ロール I/O 契約の明文化 (単一ロールから開始)
4. **Phase 4** — 並列実行パターンの導入 (必要に応じて)
5. **Phase 5** — その他の運用文書 (loop-guard.md 等) との整合 (**詰まった時だけ**)

各 Phase は独立した PR で導入し、1 PR で複数 Phase を混ぜない。

## 参照

- `CLAUDE.md` — プロジェクト運用規約 (5 時間ルール、ループ構成、STABLE 判定など)
- `AGENTS.md` — Codex コマンドの使い分け表と返却フォーマットの詳細
- Anthropic: *Multi-agent coordination patterns*

## 本ファイルの位置づけ (まとめ)

| 種類 | 既存ファイル | 本ファイル |
|---|---|---|
| 性格 | 運用規約 (強制) | リファレンス (参考) |
| 権威 | 実運用で直接使われる | 将来の設計の起点 |
| 変更の影響 | 直接影響 | 影響なし (独立) |
| 編集時の整合確認対象 | 相互参照多数 | なし (自己完結) |

このファイルは他の運用文書と **競合せず、共存する**。
