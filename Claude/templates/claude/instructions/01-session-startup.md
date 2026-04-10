# セッション開始・前提条件

## LOOP_COMMANDS

```text
/loop 30m ClaudeOS Monitor
/loop 2h ClaudeOS Development
/loop 1h ClaudeOS Verify
/loop 1h ClaudeOS Improvement
```

4つ全て登録されたら次に進む。

## Codex統合（必須）

本環境では Codex Plugin がインストール済みであることを前提とする。

- `codex-plugin-cc`
- `/codex:*` コマンド利用可能
- Review / Rescue / Status 有効
- Review Gate はリリース直前のみ有効化

### 標準実行

```text
/codex:setup
/codex:status
```

### リリース前のみ

```text
/codex:setup --enable-review-gate
```

## 実行方針

- 設定された時間から5時間作業を厳密に守る
- Monitor、Development、Verify、ImprovementをN回ループ（ループ回数はCTO判断）

### 1. AgentTeams活用ルール

Agent Teams は以下の場面で必ず起動すること：

| 場面 | 起動するAgent |
|---|---|
| フェーズ開始時 | 04-agent-teams.md の起動順序に従う |
| PR作成前 | Reviewer → Security |
| CI失敗時 | Debugger → Developer → QA |
| Issue生成時 | ProductManager → Analyst |
| リリース判断時 | ReleaseManager → CTO |

Agent Teams 不要の場面: 1ファイルの小修正、Lint修正のみ、ドキュメント更新のみ

### 2. Auto Mode（自律開発）

- ユーザーの入力を待たずに自律的に開発を進める
- 判断に迷った場合は state.json の priority.weights に基づいて決定する
- 詳細は「自律継続ルール」セクションを参照

### 3. リアルタイム可視化ルール

以下のタイミングで状態テーブルを出力すること：

| タイミング | 出力内容 |
|---|---|
| フェーズ開始時 | フェーズ名、対象Issue、目標 |
| フェーズ完了時 | 成果サマリー、CI結果、次フェーズ |
| Agent発言時 | `[ロール名] 内容:` のログフォーマット |
| CI結果判明時 | 成功/失敗テーブル |
| エラー発生時 | エラー内容、原因分析、対応方針 |
| ループ完了時 | ループ番号、KPI進捗、残時間、Token残量 |

### 4. ドキュメント確認・更新ルール

| タイミング | 対象ファイル | アクション |
|---|---|---|
| Monitor開始時 | README.md, CLAUDE.md | 差分確認（実態との乖離チェック） |
| 機能追加・変更後 | README.md | セットアップ手順・機能一覧を更新 |
| アーキテクチャ変更後 | README.md | アーキテクチャ図・フロー図を更新 |
| CI構成変更後 | README.md | CI/CD構成セクションを更新 |
| セッション終了時 | README.md, state.json | 終了時サマリー・状態を更新 |

### 5. README.md更新ルール

README.md は外部説明に耐える品質を維持する。以下を必ず含めること：

- 表を多用（設定値、機能一覧等）
- アイコンを活用（セクション見出し等）
- Mermaid等のダイアグラム図（アーキテクチャ、処理フロー）
- 初見でも理解可能な構成

更新トリガー: 利用者が触る機能・セットアップ手順・アーキテクチャ・品質ゲートのいずれかが変わった時

### 6. GitHub Projects更新ルール

| タイミング | アクション |
|---|---|
| Issue生成時 | Projectに紐付け、Status=Backlog or Todo |
| 開発着手時 | Status=In Progress |
| PR作成時 | Status=Review |
| CI確認中 | Status=Verify |
| マージ完了時 | Status=Done |
| ブロック時 | Status=Blocked |
| フェーズ完了時 | 関連Issueのステータスを一括更新 |
| セッション終了時 | 全Issueの最新ステータスを反映 |

## 自律継続ルール（最重要）

本システムは完全自律運用である。以下を厳守すること：

- **フェーズ間でユーザーの確認・承認を求めて停止してはならない**
- 実装完了後は自動的に commit → push → PR → Verify へ進むこと
- 「次に進みますか？」「確認しますか？」等の質問は禁止
- 各フェーズ完了時はログを出力し、即座に次フェーズへ移行すること
- commit / push / PR作成 / merge はすべて自律的に実行すること
- 停止が許されるのは「自動停止条件」に該当した場合のみ

## Agent定義

Agent は以下を唯一の定義ソースとする：

👉 `~/.claude/claudeos/`

### 原則

- 本書内の Agent 名は論理ロール名とする
- 実体の Prompt / Role / Behavior は claudeos 側定義を優先する
- 差異がある場合は claudeos 側を正とする
