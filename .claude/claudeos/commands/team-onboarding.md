# /team-onboarding

現在のプロジェクトを解析し、プロジェクト固有の `ONBOARDING.md` を動的生成するコマンドです。

ClaudeOS フレームワーク全般の説明ではなく、**このリポジトリで実際に何をどう扱うか** を、
実データ（`CLAUDE.md` / `state.json` / `.claude/claudeos/` / Git 履歴 / セッション学習履歴）から
抽出して記述します。

---

## 実行契約（Claude はこの順で tool を起動すること）

以下は説明ではなく **Claude への命令列** です。ステップを飛ばさず、順に実行してください。
各ステップの「入力」が揃わない場合は、該当ステップで代替動作に切り替え、生成物にその旨を明記します。

### Phase A: プロジェクト判定

1. **CWD 取得**: `Bash("pwd")` で現在のプロジェクトルートを取得する
2. **Git 情報取得**: 並列で `Bash("git remote get-url origin")` と `Bash("git rev-parse --abbrev-ref HEAD")` を実行
3. **CLAUDE.md 存在確認**: `Read("./CLAUDE.md")` — 存在しない場合は Phase B に進まず、以下のメッセージで中断:
   ```
   このプロジェクトには CLAUDE.md が存在しないため、/team-onboarding は実行できません。
   先に ClaudeOS の初期化を実施してください。
   ```
4. **Project Switch Engine 判定**: `Glob(".loop-project-exclude.md")` と `Glob(".loop-project-override.md")` を並列実行
   - `exclude` が存在 → 対象外プロジェクトとして中断（Onboarding 不要）
   - `override` が存在 → 内容を読み取り、後続 Phase の判定に優先適用

### Phase B: 設定データ収集

**必ず単一メッセージ内で並列実行すること。** 逐次実行は禁止（Phase B だけで数秒〜十数秒のロスが発生するため）。

以下 6 件の tool 呼び出しを **同一の assistant メッセージ内に束ねる**:

```
並列バッチ例（疑似コード）:
  Read("./CLAUDE.md")
  Read("./state.json")
  Read("./README.md")
  Glob(".claude/claudeos/agents/**/*.md")
  Glob(".claude/claudeos/commands/*.md")
  Read(".claude/claudeos/hooks/hooks.json")
```

| 取得対象 | tool | 存在しない場合 |
|---|---|---|
| `./CLAUDE.md` | `Read` | Phase A で弾くので到達しない |
| `./state.json` | `Read` | 動的生成前で未存在が通常。欠損時は `CLAUDE.md` §4 Goal Driven System から Goal / KPI の初期値テンプレを抽出 |
| `./README.md` | `Read` | `*README 未整備 — プロジェクト概要セクションは空欄のまま出力*` |
| `.claude/claudeos/agents/` | `Glob("**/*.md")` | `*Agent Teams 未整備 — .claude/claudeos/agents/ ディレクトリなし*` |
| `.claude/claudeos/commands/` | `Glob("*.md")` | `*コマンド未整備 — .claude/claudeos/commands/ ディレクトリなし*` |
| `.claude/claudeos/hooks/hooks.json` | `Read` | `*フック未設定 — hooks.json 未配置*` |

並列化が守られない場合の運用コストは、各 tool 呼び出しのラウンドトリップ遅延 × 6 倍。Claude Code の tool dispatcher は独立した呼び出しを物理的に並列化するため、**1 メッセージに全部入れる** のが唯一の最適化手段。

> **Note (v3.2.3)**: 旧版では `.claude/claudeos/CLAUDE.md` も並列 Read の対象に含めていたが、v3.2.3 でこのファイルは v6 旧スタイル残存だったため削除された。v8.2 以降、プロジェクト運用規約の真正値は `./CLAUDE.md` と `.claude/claudeos/system/*.md` 群であり、`.claude/claudeos/` 直下の `CLAUDE.md` は参照しない。

### Phase C: 禁止事項・運用規約の動的抽出

**ハードコード禁止。** 必ず現時点の CLAUDE.md から抽出する。

1. `Grep(pattern="^## .*禁止", path="./CLAUDE.md", output_mode="content", -A=30)` — `## 18. 禁止事項` セクションを取得
2. リスト項目（`- ` で始まる行）を **すべて** 抽出し、件数を明示して ONBOARDING.md に転記
3. CLAUDE.md のバージョン（例: `ClaudeOS v8`）も同様に先頭から抽出

### Phase D: state.json からの実践知抽出（存在時のみ）

`state.json` が存在した場合、**10 ブロック構造** を前提に以下を読む:

| ブロック | 抽出対象 |
|---|---|
| `project` | プロジェクト識別情報 |
| `goal` | 現在の目標（title / description） |
| `kpi` | 達成目標値と現在値 |
| `execution` | `phase` / `remaining_minutes` — 進行中であれば再開ポイント扱い |
| `automation` | `auto_issue_generation` / `self_evolution` フラグ |
| `priority` | 優先順位リスト |
| `learning` | `failure_patterns` / `success_patterns` — これが最重要。最大 5 件を「このプロジェクトでよくハマる点」として転記 |
| `github` | Projects / Issues / PR の最新状態 |
| `status` | ループ実行状態 |
| `codex` | `last_review_status` / `blocking_issues` — 未解決の重大指摘があれば Onboarding 先頭で警告 |

ブロックが存在しない場合はスキップし、Phase E の該当セクションに「state.json に該当情報なし」と明記。

### Phase E: ONBOARDING.md 生成

出力先は **`./ONBOARDING.md`** 固定（プロジェクトルート）。既存ファイルがあれば上書きし、
上書き前に先頭 10 行を読み取って「前回生成日時」と差分をログ出力する。

`Write("./ONBOARDING.md", content)` で以下の構造を書き出す:

```markdown
# {プロジェクト名} Onboarding

> このファイルは `/team-onboarding` により自動生成されます。
> 手動編集は次回実行時に上書きされます。恒久的な記述は CLAUDE.md または docs/ に配置してください。

**生成日時**: {ISO8601 UTC}
**ClaudeOS バージョン**: {CLAUDE.md から抽出}
**Git ブランチ**: {現在ブランチ}
**リポジトリ**: {origin URL}

## 1. このプロジェクトの Goal

{state.json.goal があればそれ、無ければ CLAUDE.md §4 の state.json 構造例から推定}

欠損時の定型: `*未設定 — state.json 未存在のため CLAUDE.md §4 のテンプレートから推定*`

## 2. 現在の KPI 状態

{state.json.kpi ブロックの転記}

欠損時の定型: `*未計測 — state.json 未存在*`

## 3. よくハマるポイント（実履歴からの抽出）

{state.json.learning.failure_patterns 上位 5 件}

欠損時の定型: `*抽出不可 — state.json.learning.failure_patterns 未存在。初回セッション後に蓄積される*`

## 4. 過去の成功パターン

{state.json.learning.success_patterns 上位 5 件}

欠損時の定型: `*抽出不可 — state.json.learning.success_patterns 未存在*`

## 5. 利用可能な Agent Teams

{`.claude/claudeos/agents/*.md` を Glob し、カテゴリグループで列挙}

**サイズ上限**: このセクションは **最大 3 KB**（約 80 行）に収める。
- 件数 ≤ 20: ファイル名とフロントマターの description を表形式で全列挙
- 件数 > 20: カテゴリグループ（統括 / 設計 / 実装 / レビュー / QA / 運用 / 改善など）で集約し、各カテゴリ内はファイル名のみ列挙。full description は `.claude/claudeos/agents/{name}.md` を直接参照するよう誘導
- 欠損時の定型: `*Agent Teams 未整備 — .claude/claudeos/agents/ ディレクトリなし*`

## 6. 利用可能なスラッシュコマンド

{`.claude/claudeos/commands/*.md` を列挙}

**サイズ上限**: このセクションは **最大 3 KB**（約 80 行）に収める。
- 件数 ≤ 20: 各ファイルの先頭行（タイトル）と 2-3 行目を description として取得
- 件数 > 20: カテゴリグループ（計画 / レビュー / テスト / 学習 / ドキュメントなど）で集約し、各カテゴリ内はコマンド名のみ列挙
- 欠損時の定型: `*コマンド未整備 — .claude/claudeos/commands/ ディレクトリなし*`

## 7. 禁止事項（CLAUDE.md §18 の全項目を動的ミラー）

{Phase C で抽出した全項目。N 件あれば N 件すべて}

## 8. 直近の Git 活動

**件数は動的に決定する。** 以下の優先順で判定:

1. `state.json.execution.phase` が存在し remaining_minutes > 0（セッション進行中）→ `git log --oneline -30`
2. `Bash("git log -1 --format=%cr")` の相対日付が `days` 未満（active プロジェクト）→ `git log --oneline -30`
3. `days` 以上 `weeks` 未満 → `git log --oneline -20`
4. `weeks` 以上（dormant）→ `git log --oneline -10`

固定の `-20` は使用しない。上記判定結果を ONBOARDING.md の本セクション先頭に `（直近 N 件 / active 判定）` として 1 行で明示する。

欠損時の定型: `*git history 取得不可 — Git リポジトリ未初期化*`

## 9. 未解決の Codex 指摘（state.json.codex.blocking_issues があれば）

{重大指摘リスト}

欠損時の定型: `*未解決指摘なし — state.json.codex.blocking_issues 未存在または空*`

## 10. セッション開始手順

CLAUDE.md §0 の 4 ループ登録コマンドを、**このプロジェクトの state.json から抽出した** 時間配分で生成:

{state.json.execution.loop_distribution があればそれを優先、無ければ CLAUDE.md §0 デフォルト値}

## 11. 再開ポイント（前回セッション未完了時）

{state.json.execution.phase が Monitor/Development/Verify/Improvement のいずれかで残時間 > 0 なら、そのフェーズの再開手順}
```

### Phase F: Verify ループ連動の登録

STABLE 達成時に ONBOARDING.md を自動再生成するフックを提案する。

1. `.claude/claudeos/hooks/hooks.json` に以下のエントリが存在しない場合、追記を **提案する**（勝手に編集しない。ユーザー確認後に Edit）:
   ```json
   {
     "PostToolUse": [
       { "name": "onboarding-refresh-on-stable", "description": "STABLE 判定成立時に /team-onboarding を再実行し ONBOARDING.md を更新" }
     ]
   }
   ```
2. 実フックスクリプトは別途 `.claude/claudeos/hooks/onboarding-refresh-on-stable.md` として配置する設計を提示（別 Issue 化を推奨）

### Phase G: 完了報告

最後に以下を表示する:

```
✅ ONBOARDING.md を生成しました
   - パス: ./ONBOARDING.md
   - サイズ: {N} バイト
   - 反映した禁止事項: {N} 件（CLAUDE.md §18 から動的抽出）
   - 反映した失敗パターン: {N} 件（state.json.learning から）
   - 反映した成功パターン: {N} 件
   - 反映した Agent: {N} 件
   - 反映した Command: {N} 件
   - Verify 連動フック: 未登録（登録を提案済み / 既登録）
```

---

## 設計原則

- **静的記述を ONBOARDING.md に書かない**: CLAUDE.md や state.json が唯一の真実であり、このコマンドは抽出器
- **欠損時の退避動作を必ず明示**: state.json が無い新規プロジェクトでも動作する
- **Project Switch Engine 対応**: `.loop-project-exclude.md` / `.loop-project-override.md` を判定に組み込む
- **禁止事項は動的ミラー**: CLAUDE.md §18 が更新されれば次回実行時に自動追従
- **Verify 連動の自動更新**: STABLE 達成を契機に再実行される仕組みを提示
- **出力先は固定**: `./ONBOARDING.md`（プロジェクトルート）
- **Phase B は単一メッセージ内の並列実行**: 逐次実行を禁止し、7 件を 1 バッチ化
- **出力セクションにサイズ上限**: Section 5 / 6 は最大 3 KB（Agent / Command が多いリポジトリで肥大化しない）
- **Git log 件数は動的決定**: セッション進行中・active・dormant の判定により 10 / 20 / 30 件を切り替え
- **欠損時メッセージは統一フォーマット**: `*{理由} — {詳細}*` の斜体単行形式（見出しの下の空白行を減らす）

## 既知の制約

- state.json の 10 ブロック構造はプロジェクトにより差があるため、欠損ブロックはスキップする
- `.loop-project-override.md` のスキーマは未確定 — 初期実装では「存在すれば対象」として扱い、将来拡張する
- Verify 連動フックの実体スクリプトは本コマンドでは生成せず、登録提案に留める（権限境界の明確化）

## 参照先

| 対象 | 場所 |
|---|---|
| プロジェクト運用規約 | `./CLAUDE.md` |
| グローバル運用規約 | `~/.claude/CLAUDE.md` |
| state.json 構造定義 | `./CLAUDE.md` §4 |
| 禁止事項の正 | `./CLAUDE.md` §18 |
| Agent 定義 | `.claude/claudeos/agents/` |
| Hook 定義 | `.claude/claudeos/hooks/hooks.json` |
