# Role Contracts (Orchestrator-Subagent)

このファイルは ClaudeOS における全ロールの **契約** を定義する唯一のソースである。
Anthropic の multi-agent coordination 原則に従い、既定パターンは **Orchestrator-Subagent** のみとし、他の協調パターン (Message Bus / Shared State / Event-driven) は「詰まった地点でのみ」追加する。

優先順位: 本ファイル > 個別 agent 定義 > 本文説明。

---

## 0. 基本方針 (Anthropic 原則)

1. 最も単純に動く形から始め、詰まった地点でのみ複雑化する。
2. Orchestrator-Subagent を既定とする。message bus は CI/Issue/PR イベントから段階導入する。
3. 全エージェントを最初からイベント駆動にしない。
4. 役割が多いほど中央要約の情報欠落対策が重要になる → 返却を構造化する。
5. 共有状態を使う場合は「終了条件」と「truth source」を先に定義する。

---

## 1. 運用モード (Light / Full)

小タスクで Full Orchestration を走らせない。モード選択は **Orchestrator の最初の判断** とする。

| モード | 発動条件 | 起動ロール | 最大コンテキスト |
|---|---|---|---|
| **light** | 1ファイル修正 / lint / doc / 既知バグ / 差分 < 50行 | Developer のみ (+ 必要時 Reviewer) | 10% |
| **full** | 新機能 / 認証権限変更 / DBスキーマ / 並列同期 / 差分 ≥ 50行 or 3ファイル以上 | role chain 全員 | 上限まで |

- 既定は **light**。full への昇格は Orchestrator が理由付きで宣言する。
- light モードでは Architect / Security / Analyst / EvolutionManager を呼ばない。
- Improvement ループは light の時に省略してよい。

---

## 2. 返却フォーマット (全サブエージェント共通・必須)

サブエージェントの返却は **自由記述ではなく以下4セクション固定、順序固定**。長文禁止、各セクション箇条書き。

```markdown
## Summary
- 1〜3行の結論 (最も重要なリスクから書き始める。賞賛から始めない)

## Risks
- 未確認点・前提破れ・副作用候補を列挙する (空なら "none")
- 重大度 (high / medium / low) を付与する

## Findings
- 観測事実のみ (根拠ファイル:行番号を添える)

## Next Action
- Orchestrator が次に踏むべき1手 (候補1〜3)
```

**順序は全役割共通で固定** (Reviewer も同じ)。Risks が Findings より前に置かれているのは、重要な論点が埋もれないようにするため。
Orchestrator はこの 4 セクションが揃っていない返却を受領しない。

---

## 3. ロール契約 (I/O / 完了条件 / 禁止事項 / 参照許可)

各ロールは **入力・出力・完了条件・禁止事項・参照許可ファイル群** を必ず持つ。
未定義のロールを起動しないこと。

### 3.1 Orchestrator (CTO 兼)

| 項目 | 定義 |
|---|---|
| 入力 | TASKS.md 先頭タスク, state.json, Loop Guard 状態 |
| 出力 | モード宣言 (light/full), 起動するサブエージェント名, タスク分解 |
| 完了条件 | サブエージェントから4セクション返却を受領、または Loop Guard 停止 |
| 禁止事項 | 自身でコード編集を行う (分解と統制に専念), 理由なし full 昇格 |
| 参照許可 | リポジトリ全域 (読み取り), `state.json` (書き込み) |

### 3.2 Architect

| 項目 | 定義 |
|---|---|
| 入力 | 変更要求, 影響範囲候補 |
| 出力 | 責務分離案, 境界提案, 差分スコープ |
| 完了条件 | full モードかつ差分 ≥ 50行 or 3ファイル以上の時のみ呼ばれる。それ以外はスキップ |
| 禁止事項 | light モードでの呼び出し, コード実装 |
| 参照許可 | `docs/`, `README.md`, `src/` 読み取り |

### 3.3 Developer

| 項目 | 定義 |
|---|---|
| 入力 | 1つの論理修正対象 + 完了判定 |
| 出力 | コード差分 + 論理的完了単位コミット |
| 完了条件 | 自分の担当ファイル境界内でテスト追加 or 既存テスト実行成功 |
| 禁止事項 | 担当外ファイルへの変更, 1コミットに複数論理変更, `main` 直 push |
| 参照許可 | Orchestrator が与えた担当ファイル群のみ (並列実行時は重複禁止) |

### 3.4 Reviewer (Codex Plugin 経由)

| 項目 | 定義 |
|---|---|
| 入力 | PR 差分 or ローカル差分 |
| 出力 | §2 の共通4セクション (Summary → Risks → Findings → Next Action)。Summary の冒頭は最も重大なリスクで始める |
| 完了条件 | `/codex:review` 完了 + Risks セクションに severity 判定 |
| 禁止事項 | Claude 単独レビュー (必ず Codex Plugin を使う), Summary を賞賛・謝辞から始めること, §2 と異なる順序や節構成で返却すること |
| 参照許可 | 差分対象ファイル + 直接依存ファイル |

### 3.5 Debugger (Codex Rescue 経由)

| 項目 | 定義 |
|---|---|
| 入力 | 1つの仮説 + 1つの失敗カテゴリ |
| 出力 | 原因候補, 最小修正案 |
| 完了条件 | 1 rescue = 1 仮説で判定可能になった時点 |
| 禁止事項 | 大規模書換え, 深追い (同一原因 3 回超), 推測修正 |
| 参照許可 | 失敗ログ関連ファイルのみ |

### 3.6 QA

| 項目 | 定義 |
|---|---|
| 入力 | 変更範囲 + 受入条件 |
| 出力 | 検証結果表 (test / lint / build / typecheck) |
| 完了条件 | 「変更理由」と「テスト意図」の整合確認を含む |
| 禁止事項 | テスト成功だけで完了宣言 (意図整合を必ず見る) |
| 参照許可 | test/, spec/, e2e/ |

### 3.7 Security

| 項目 | 定義 |
|---|---|
| 入力 | 差分 |
| 出力 | 重大度付き指摘 (critical/high/medium/low) |
| 完了条件 | **以下の差分がある時のみ深く起動**: 認証, 権限, 外部公開 API, secrets, 依存追加/更新 |
| 禁止事項 | 上記差分なしでの full 起動, severity 判断なしの指摘 |
| 参照許可 | 差分対象 + 依存マニフェスト (package.json 等) |

### 3.8 DevOps (Ops)

| 項目 | 定義 |
|---|---|
| 入力 | CI 状態, Projects 状態 |
| 出力 | ライトチェック or フルチェック結果 |
| 完了条件 | ライト: CI status + 最新 run 番号のみ / フル: logs + failure category 分類 |
| 禁止事項 | 毎回フル確認 (light モード時はライトチェックのみ) |
| 参照許可 | `.github/`, CI ログ |

### 3.9 Analyst / EvolutionManager

full モード時のみ起動。light モードでは呼ばない。

---

## 4. 並列実行の安全ルール

Agent Teams を並列起動する場合、以下を **先に** 決めること:

1. **担当ファイル境界**: エージェントごとに触ってよいファイル/ディレクトリを排他的に割り当てる。
2. **共有ファイルの書き込み権限は 1 エージェントのみ**: README.md, CLAUDE.md, state.json などは Orchestrator だけが書く。
3. **終了条件の3系統**: `時間 (max duration)` / `収束 (no-change N回)` / `担当判定 (Orchestrator の強制終了)` のいずれかで必ず終わる。
4. **Shared State を使う場合は truth source を明文化**: どのファイルが唯一の真実か、更新順序はどうかを先に書く。

---

## 5. Truth Source 一覧

| 情報 | Truth Source | Writer |
|---|---|---|
| タスクキュー | `TASKS.md` (唯一。他の場所にキューを作らない) | 人間 + Issue Factory |
| 実行状態 | `state.json` | **scoped ownership** (下記 §5.1 参照) |
| 進行中の観測 | `.loop-monitor-report.md` (観測専用、判定結論を書かない) | Monitor Loop |
| 検証結果 | `.loop-verify-report.md` (判定専用) | Verify Loop |
| 引継ぎ情報 | `.loop-handoff-report.md` (再開専用) | **Loop Guard のみ** |
| 長期記憶 | Memory MCP | Orchestrator |
| 作業規約 | 本ファイル (`role-contracts.md`) | 人間 |
| 運用規約 | `CLAUDE.md` | 人間 |

### 5.1 `state.json` の scoped ownership

`state.json` は唯一の実行状態ソースだが、単一 writer にすると各ループが handoff 情報を残せなくなるため、**キー単位で書き込み権限を分割** する (append-only セマンティクス):

| キー範囲 | Writer | アクセス |
|---|---|---|
| `execution.phase`, `execution.elapsed_minutes`, `execution.remaining_minutes`, `execution.mode`, `execution.last_stop_reason` | Orchestrator | 上書き可 |
| `execution.no_progress_streak`, `execution.same_diff_streak`, `execution.retry_count_by_cause`, `debug.*` | Loop Guard | 上書き可 |
| `execution.pending` | Build Loop | **append-only** (既存要素を消さない) |
| `execution.pending_verify` | Verify Loop | **append-only** (既存要素を消さない) |
| それ以外 (`project`, `goal`, `kpi`, `token`, `stable`, `session`, `codex`, `automation`, `learning`, `github`, `status`) | Orchestrator | 上書き可 |

**原則**:
- Build / Verify は自分の担当キーのみ append する (他のキーを読み書きしない)
- Loop Guard は Build/Verify が追記した `pending` / `pending_verify` を読み、停止時に `.loop-handoff-report.md` を合成する
- 同時書き込みの整合性は Orchestrator が管理する (並列起動時は role-contracts §4 の並列ルールに従う)

### 5.2 その他の原則

- 同じ情報を 2 箇所に書かない。分裂した時は truth source を信じる。
- **`.loop-handoff-report.md` は Loop Guard 単独 writer**。Build / Verify / Improve ループはこのファイルを直接書かず、未完了情報を上記 §5.1 の `state.json.execution.pending` / `pending_verify` へ追記する。Loop Guard が停止時に `state.json` を読んで handoff レポートを生成する。
- 観測ファイル (`.loop-monitor-report.md`) と判定ファイル (`.loop-verify-report.md`) の責務を混ぜない。Monitor は判定結論を書かない。

---

## 6. Orchestrator の判断フロー

```text
新タスク受領
  ↓
TASKS.md の先頭を確認
  ↓
差分スコープ推定 → light / full 決定
  ↓
light: Developer 単独起動 → 返却受領 → commit → Verify (最小)
full:  role chain 起動 → 返却受領 → Reviewer → Verify (完全) → Improvement
  ↓
Loop Guard 判定 → 次ループ or 停止
```

---

## 7. 禁止事項 (総則)

- 本契約を満たさないサブエージェントの起動
- 返却4セクションを欠いた受領の承認
- light モードで Architect / Security / Analyst / EvolutionManager を呼ぶこと
- 担当ファイル境界を宣言せずに並列起動
- Improvement を必須扱いにすること (余力時のみ条件付きで起動)
- 自動生成タスクを triage 無しで即実行すること (3件上限 + 根拠ファイル + 再現条件が必須)

---

## 8. 参照

- `system/orchestrator.md` — Orchestrator の実行サイクル
- `system/loop-guard.md` — 停止条件と拡張 state スキーマ
- `loops/*-loop.md` — 各ループの責務チェックリスト
- `AGENTS.md` — Codex `exec/review/resume/fork` 使い分け表
