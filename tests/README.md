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

### unit/

外部ファイル・git・ネットワークに依存しない純粋なロジックテスト。

| ファイル | テスト対象 |
|---|---|
| `Config.Tests.ps1` | `Config.psm1` — 設定読み込み・検証 |
| `ErrorHandler.Tests.ps1` | `ErrorHandler.psm1` — エラー処理ユーティリティ |
| `LauncherCommon.Tests.ps1` | `LauncherCommon.psm1` — ランチャー共通関数 |
| `MessageBus.Tests.ps1` | `MessageBus.psm1` — メッセージバス |
| `TokenBudget.Tests.ps1` | `TokenBudget.psm1` — トークン予算管理 |

### integration/

モジュール間連携や git worktree 操作など、実際のファイルシステムを使うテスト。

| ファイル | テスト対象 |
|---|---|
| `AgentTeams.Tests.ps1` | `AgentTeams.psm1` — エージェントチーム管理 |
| `ArchitectureCheck.Tests.ps1` | `ArchitectureCheck.psm1` — アーキテクチャ違反検出 |
| `ClaudeOSPlugin.Tests.ps1` | `ClaudeOSPlugin.psm1` — Claude OS プラグイン |
| `Diagnostics.Tests.ps1` | `Diagnostics.psm1` — 診断ツール |
| `IssueSyncManager.Tests.ps1` | `IssueSyncManager.psm1` — Issue 同期管理 |
| `McpHealthCheck.Tests.ps1` | `McpHealthCheck.psm1` — MCP ヘルスチェック |
| `SelfEvolution.Tests.ps1` | `SelfEvolution.psm1` — 自己進化エンジン |
| `SSHHelper.Tests.ps1` | `SSHHelper.psm1` — SSH ヘルパー |
| `StartScripts.Tests.ps1` | 各種起動スクリプト |
| `Sync-Issues.Tests.ps1` | `Sync-Issues.ps1` — Issue 同期スクリプト |
| `WorktreeManager.Tests.ps1` | `WorktreeManager.psm1` — Worktree 管理 |

### smoke/

リポジトリ全体が想定どおりの構造を持つことを確認する E2E テスト。

| ファイル | テスト対象 |
|---|---|
| `E2E.Tests.ps1` | 必須ファイル・ディレクトリ構造・hooks.json・state.json.example スキーマ |

## 実行方法

```powershell
# 全テスト実行
Invoke-Pester .\tests -Output Detailed

# カテゴリ別実行
Invoke-Pester .\tests\unit        -Output Detailed
Invoke-Pester .\tests\integration -Output Detailed
Invoke-Pester .\tests\smoke       -Output Detailed
```

CI では `.\tests` をルートとして再帰検索するため、サブディレクトリ追加時も CI 設定変更は不要です。
