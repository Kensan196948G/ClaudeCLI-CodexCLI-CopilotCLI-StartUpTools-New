# everything-claude-code

Claude Code を完全自立型開発モードで運用するための統合プラグインパックです。

このパックは、単発の補助ではなく、調査、設計、実装、検証、改善、文書化、GitHub 連動、Agent Teams オーケストレーションまでを一つの運用体系として扱います。

## 🚀 このパックの狙い

- Claude Code を業務レベルの自律開発エージェントとして使える状態にする
- Agent Teams、SubAgents、Hooks、Git WorkTree、MCP、GitHub Projects、GitHub Actions を一貫運用できるようにする
- 8 時間上限、Loop Guard、STABLE 判定、再開容易性を明文化して暴走を防ぐ

## 🧠 完全自立型開発モード

このパックは `CLAUDE.md` を中核にして運用します。

基本方針は次のとおりです。

- `/loop 1h Monitor`
- `/loop 2h Development`
- `/loop 2h Verify`
- `/loop 3h Improvement`
- 8 時間上限で安全停止
- Agent Teams 会話の可視化
- README とドキュメントの継続更新
- GitHub Projects と GitHub Actions を品質ゲートとして活用

## 📦 何が入っているか

| パス | 役割 |
|---|---|
| `CLAUDE.md` | 完全自立型開発モードの中核ポリシー |
| `.claude-plugin/` | プラグインメタ情報、マーケットプレイス定義 |
| `system/` | Orchestrator、Loop Guard、Token Budget などのコア文書 |
| `executive/` | CTO、Architecture Board などの判断レイヤ |
| `management/` | Scrum Master、Dev Factory などの管理レイヤ |
| `loops/` | Monitor、Build、Verify、Improve のループ定義 |
| `ci/` | CI を品質ゲートとして扱うための基準 |
| `evolution/` | 学びと改善の蓄積 |
| `agents/` | 30 体の専門サブエージェント |
| `skills/` | 分野別、技術別、運用別の実務ガイド |
| `commands/` | `/plan`、`/verify` などの操作入口 |
| `rules/` | 常時守るべき品質、Git、テスト、セキュリティ原則 |
| `hooks/` | セッション前後や圧縮時の自動処理 |
| `scripts/` | hooks や導入補助の Node.js スクリプト |
| `tests/` | プラグイン内補助コードのテスト |
| `contexts/` | 開発、レビュー、調査のモード別文脈 |
| `examples/` | 実案件向け設定例 |
| `mcp-configs/` | MCP サーバ設定例 |
| `docs/` | 導入手順書、運用ガイド |

## 🔁 運用ループ

このパックは次の 4 ループで開発を進めます。

| ループ | 役割 | 主な内容 |
|---|---|---|
| 🔍 Monitor | 現状把握 | GitHub、CI、Issue、Projects、README、制約確認 |
| 🔨 Development | 変更実施 | 設計、実装、修復、WorkTree 管理 |
| ✔ Verify | 品質確認 | test、lint、build、security、CI 確認 |
| 🔧 Improvement | 整備 | リファクタリング、技術負債解消、README 最終整備 |

重要なのは、**ループ判定は時間ではなく主作業内容で行う** ことです。  
詳しくは `CLAUDE.md` と `loops/verify-loop.md` を参照してください。

## 🤖 Agent Teams 前提の使い方

このパックでは、複雑なタスクほど Agent Teams を前提に運用します。

### 主なロール

| ロール | 対応 agent |
|---|---|
| 🧠 CTO | `loop-operator`, `planner` |
| 🏗 Architect | `architect`, `api-designer` |
| 👨‍💻 Developer | 技術別 reviewer / resolver、`build-error-resolver` |
| 🔎 Reviewer | `code-reviewer` |
| 🧪 QA | `tdd-guide`, `e2e-runner`, `qa-agent` |
| 🔐 Security | `security-reviewer` |
| 🚀 DevOps | `devops-agent`, `release-manager` |

### 可視化ルール

Agent Teams の議論は `CLAUDE.md` に定義された形式で表示し、CTO、Architect、Developer、Security、QA、DevOps の意見を明示します。

## 📄 README 自己更新方針

この README 自体も、完全自立型開発モードの考え方に従って更新します。

### 更新タイミング

| タイミング | 更新内容 |
|---|---|
| セッション開始時 | 対象プロジェクト、現在フェーズ、ループ構成 |
| 各ループ終了時 | 進捗、STABLE count、CI 状態 |
| 機能実装完了時 | 機能説明、アーキテクチャ図、変更履歴 |
| セッション終了時 | 残課題、再開ポイント、次フェーズ |

### 推奨構成

```markdown
# {プロジェクト名}

## 🚀 プロジェクト概要
## 📊 開発状況（自動更新）
## 🏗 アーキテクチャ
## ⚙️ 機能一覧
## 🔄 開発フロー
## 📋 直近の変更履歴
```

## 🛠 導入パターン

### 最小導入

- `rules/`
- `commands/`
- 必要な `skills/`

### 標準導入

- `agents/`
- `skills/`
- `commands/`
- `rules/`
- `hooks/`
- `scripts/`

### 完全導入

- `everything-claude-code` 一式を `.claude/` 配下へ配置

完全自立型開発モードを前提にする場合は、**完全導入** を推奨します。

## 📚 最初に読むべきファイル

1. `CLAUDE.md`
2. `docs/INSTALLATION.md`
3. `docs/OPERATIONS.md`
4. `system/orchestrator.md`
5. `system/loop-guard.md`
6. `loops/monitor-loop.md`
7. `loops/build-loop.md`
8. `loops/verify-loop.md`
9. `loops/improve-loop.md`

## 🎯 推奨の使い始め

1. `search-first` skill で既存コード、README、仕様を確認する
2. `/plan` で作業単位を整理する
3. 使う skills と agents を決める
4. Development に入る
5. `/verify` で STABLE 判定へ近づける
6. `/update-docs` で README と docs を同期する
7. `/learn` または `/learn-eval` で学びを残す

## 💡 運用原則

- 正規構成は `everything-claude-code` に一本化する
- 旧構成や重複フォルダは増やさない
- 外部状態が読めないときは推測しない
- README と docs の更新を後回しにしない
- STABLE 未達で merge / deploy しない
- 8 時間到達時は安全停止を優先する

## 🔗 関連ドキュメント

- `CLAUDE.md`
- `docs/INSTALLATION.md`
- `docs/OPERATIONS.md`
