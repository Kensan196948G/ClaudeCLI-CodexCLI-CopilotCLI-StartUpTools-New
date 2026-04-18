# tests/ — テスト分類ガイド

## ディレクトリ構成

```
tests/
├── unit/          # 単体テスト（外部依存なし）
├── integration/   # 統合テスト（モジュール連携・git 操作含む）
└── smoke/         # E2E スモークテスト（リポジトリ全体の構造確認）
```

## 分類基準

| ディレクトリ | 対象 | 外部依存 | 実行速度 |
|---|---|---|---|
| `unit/` | 単一モジュールの関数ロジック | なし | 高速 |
| `integration/` | 複数モジュール連携・git 操作・ファイルシステム | あり | 中速 |
| `smoke/` | リポジトリ構造・必須ファイル存在確認 | git repo 全体 | 低速 |

---

### unit/ (17 files)

外部ファイル・git・ネットワークに依存しない純粋なロジックテスト。
`scripts/lib/` の全 17 モジュールに対応する。

| ファイル | テスト対象 |
|---|---|
| `AgentTeams.Tests.ps1` | `AgentTeams.psm1` — Agent Teams ランタイム |
| `ArchitectureCheck.Tests.ps1` | `ArchitectureCheck.psm1` — アーキテクチャ違反検出 |
| `Config.Tests.ps1` | `Config.psm1` — 設定読み込み・検証 |
| `CronManager.Tests.ps1` | `CronManager.psm1` — Cron スケジュール管理 |
| `ErrorHandler.Tests.ps1` | `ErrorHandler.psm1` — エラー処理ユーティリティ |
| `IssueSyncManager.Tests.ps1` | `IssueSyncManager.psm1` — Issue/Backlog 同期 |
| `LauncherCommon.Tests.ps1` | `LauncherCommon.psm1` — ランチャー共通関数 |
| `LogManager.Tests.ps1` | `LogManager.psm1` — ログ管理 |
| `McpHealthCheck.Tests.ps1` | `McpHealthCheck.psm1` — MCP ヘルスチェック |
| `MenuCommon.Tests.ps1` | `MenuCommon.psm1` — メニュー共通処理 |
| `MessageBus.Tests.ps1` | `MessageBus.psm1` — メッセージバス |
| `SSHHelper.Tests.ps1` | `SSHHelper.psm1` — SSH ヘルパー |
| `SelfEvolution.Tests.ps1` | `SelfEvolution.psm1` — セッション学習・自己進化 |
| `SessionTabManager.Tests.ps1` | `SessionTabManager.psm1` — セッションタブ管理 |
| `StatuslineManager.Tests.ps1` | `StatuslineManager.psm1` — ステータスライン管理 |
| `TokenBudget.Tests.ps1` | `TokenBudget.psm1` — トークン予算管理 |
| `WorktreeManager.Tests.ps1` | `WorktreeManager.psm1` — Git Worktree 管理 |

---

### integration/ (11 files)

モジュール間連携や git worktree 操作など、実際のファイルシステムを使うテスト。

| ファイル | テスト対象 |
|---|---|
| `AgentTeams.Tests.ps1` | `AgentTeams.psm1` — エージェントチーム管理（連携テスト） |
| `ArchitectureCheck.Tests.ps1` | `ArchitectureCheck.psm1` — アーキテクチャ違反検出（連携テスト） |
| `ClaudeOSPlugin.Tests.ps1` | `.claude-plugin/plugin.json` — プラグイン構造・コンポーネントパス検証 |
| `Diagnostics.Tests.ps1` | `scripts/test/` 診断スクリプト — ドライブマッピング・ツール診断 |
| `IssueSyncManager.Tests.ps1` | `IssueSyncManager.psm1` — Issue 同期管理（連携テスト） |
| `McpHealthCheck.Tests.ps1` | `McpHealthCheck.psm1` — MCP ヘルスチェック（連携テスト） |
| `SelfEvolution.Tests.ps1` | `SelfEvolution.psm1` — 自己進化エンジン（連携テスト） |
| `SSHHelper.Tests.ps1` | `SSHHelper.psm1` — SSH ヘルパー（連携テスト） |
| `StartScripts.Tests.ps1` | 各種起動スクリプト（`scripts/main/`） |
| `Sync-Issues.Tests.ps1` | `Sync-Issues.ps1` — Issue 同期スクリプト |
| `WorktreeManager.Tests.ps1` | `WorktreeManager.psm1` — Worktree 管理（連携テスト） |

---

### smoke/ (1 file)

リポジトリ全体が想定どおりの構造を持つことを確認する E2E テスト。

| ファイル | テスト対象 |
|---|---|
| `E2E.Tests.ps1` | 必須ファイル・ディレクトリ構造・hooks.json・state.json.example スキーマ |

---

## 実行方法

```powershell
# 全テスト実行
Invoke-Pester .\tests -CI

# カテゴリ別実行
Invoke-Pester .\tests\unit        -Output Detailed
Invoke-Pester .\tests\integration -Output Detailed
Invoke-Pester .\tests\smoke       -Output Detailed
```

CI では `.\tests` をルートとして再帰検索するため、サブディレクトリ追加時も CI 設定変更は不要です。

## カバレッジ状況

| カテゴリ | ファイル数 | 対応する正本 |
|---|---|---|
| unit/ | 17 | `scripts/lib/` 全 17 モジュール |
| integration/ | 11 | 複数モジュール連携・スクリプト・plugin.json |
| smoke/ | 1 | リポジトリ構造全体 |
| **合計** | **29** | — |

*最終更新: 2026-04-18*
