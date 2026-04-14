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

以下を **並列で** 実行する（Read / Glob / Bash の独立呼び出しは 1 メッセージで束ねること）:

| 取得対象 | tool | 存在しない場合 |
|---|---|---|
| `./CLAUDE.md` | `Read` | Phase A で弾くので到達しない |
| `./state.json` | `Read` | 動的生成前で未存在が通常。欠損時は `CLAUDE.md` §4 Goal Driven System から Goal / KPI の初期値テンプレを抽出 |
| `./README.md` | `Read` | `README未整備` と記録 |
| `.claude/claudeos/CLAUDE.md` | `Read` | 継承なし、グローバル設定のみとみなす |
| `.claude/claudeos/agents/` | `Glob("**/*.md")` | Agent Teams 未整備として記録 |
| `.claude/claudeos/commands/` | `Glob("*.md")` | コマンド未整備として記録 |
| `.claude/claudeos/hooks/hooks.json` | `Read` | フック未設定として記録 |

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

## 2. 現在の KPI 状態

{state.json.kpi ブロックの転記、無ければ「未計測」}

## 3. よくハマるポイント（実履歴からの抽出）

{state.json.learning.failure_patterns 上位 5 件。無ければ「学習履歴なし、初回セッション後に蓄積される」}

## 4. 過去の成功パターン

{state.json.learning.success_patterns 上位 5 件。無ければ同上}

## 5. 利用可能な Agent Teams

{.claude/claudeos/agents/*.md を Glob し、ファイル名とフロントマターの description を表形式で列挙}

## 6. 利用可能なスラッシュコマンド

{.claude/claudeos/commands/*.md を列挙。各ファイルの先頭行（タイトル）と 2-3 行目を description として取得}

## 7. 禁止事項（CLAUDE.md §18 の全項目を動的ミラー）

{Phase C で抽出した全項目。N 件あれば N 件すべて}

## 8. 直近の Git 活動

{Bash("git log --oneline -20") の結果}

## 9. 未解決の Codex 指摘（state.json.codex.blocking_issues があれば）

{重大指摘リスト。無ければ「未解決指摘なし」または「state.json 未存在」}

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
