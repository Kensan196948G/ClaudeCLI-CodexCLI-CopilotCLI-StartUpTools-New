# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools

Windows から `Claude Code`、`Codex CLI`、`GitHub Copilot CLI` を統一的に起動するためのスタートアップツールです。ローカル起動と SSH リモート起動の両方に対応し、設定・診断・ガイドをこのリポジトリに集約しています。

## 対応ツール

| ツール | 提供元 | 主な用途 |
|--------|--------|---------|
| Claude Code | Anthropic | 大規模なコード修正、レビュー、実装支援 |
| Codex CLI | OpenAI | ターミナル中心のコード生成、シェル支援 |
| GitHub Copilot CLI | GitHub | `copilot --yolo` によるシェル・GitHub 操作支援 |

---

## 開発状況

| 項目 | 状態 |
|------|------|
| バージョン | v2.7.0 |
| テスト | Pester 全パス (CI) |
| CI | SUCCESS |
| ClaudeOS | v6 (Agent Teams ランタイム・MCP モジュール化版) |

### Agent Teams 対応レベル

| 機能 | レベル | 説明 |
|------|--------|------|
| Orchestrator | 3 | 起動フロー中心 |
| Project Switch | 3 | プロジェクト選択・記録・ソート |
| Monitor / Verify Loop | 3 | テスト・CI 統合 |
| Agent Teams 可視化 | 3 | ランタイムエンジン実装済み |
| MCP サーバー連携 | 4 | モジュール化・メニュー統合・テスト完備 |
| Worktree Manager | 0 | 未実装 |
| Backlog Manager | 2 | TASKS.md 同期 |

---

## アーキテクチャ

```mermaid
graph TD
    A["start.bat"] --> B["Start-Menu.ps1"]
    B --> C["Start-ClaudeCode.ps1"]
    B --> D["Start-CodexCLI.ps1"]
    B --> E["Start-CopilotCLI.ps1"]
    B --> F["Start-All.ps1"]
    B --> G["Test-AllTools.ps1"]
    B --> H["Test-McpHealth.ps1"]
    B --> I["Test-AgentTeams.ps1"]

    C --> J{"Local or SSH?"}
    D --> J
    E --> J

    J -->|Local| K["projectsDir"]
    J -->|SSH| L["linuxHost via SSH"]
    L --> M["claude_pty_bridge.py"]

    C --> N["CLAUDE.md deploy"]
    D --> O["AGENTS.md deploy"]
    E --> P["copilot-instructions.md deploy"]
```

## モジュール構成

```mermaid
graph LR
    subgraph "scripts/lib/"
        Config["Config.psm1"]
        Launcher["LauncherCommon.psm1"]
        Menu["MenuCommon.psm1"]
        SSH["SSHHelper.psm1"]
        Error["ErrorHandler.psm1"]
        MCP["McpHealthCheck.psm1"]
        AT["AgentTeams.psm1"]
    end

    subgraph "診断・ランタイム"
        TAT["Test-AllTools.ps1"] --> Config
        TAT --> Launcher
        TAT --> MCP
        TMH["Test-McpHealth.ps1"] --> MCP
        TAG["Test-AgentTeams.ps1"] --> AT
    end

    subgraph "起動スクリプト"
        SC["Start-ClaudeCode.ps1"] --> Launcher
        SC --> Config
        SM["Start-Menu.ps1"] --> Launcher
        SM --> Config
        SM --> Menu
    end
```

## 自律開発フロー

```mermaid
flowchart LR
    M["Monitor<br/>30m"] --> B["Development<br/>2h"]
    B --> V["Verify<br/>1h"]
    V --> I["Improvement<br/>1h"]
    I -->|STABLE未達| B
    I -->|STABLE達成| S["Deploy"]
    V -->|CI失敗| R["Auto Repair"]
    R --> V
```

## Agent Teams ランタイム

```mermaid
flowchart TD
    Task["Task Description"] --> Analyze["Get-TaskTypeAnalysis<br/>17パターン分類"]
    Task --> Rules["Get-BacklogRuleMatch<br/>backlog-rules.json"]
    Analyze --> Team["New-AgentTeam"]
    Rules --> Team

    Team --> Core["Core Team<br/>7 Roles"]
    Team --> Spec["Specialists<br/>auto-selected"]

    Core --> CTO["CTO"]
    Core --> Arch["Architect"]
    Core --> Dev["Developer"]
    Core --> QA["QA"]
    Core --> Sec["Security"]
    Core --> Ops["DevOps"]
    Core --> Rev["Reviewer"]

    Spec --> S1["37 Agent定義から<br/>タスク種別で自動選定"]
```

---

## 主な機能

| 機能 | 説明 |
|------|------|
| 統一起動メニュー | `start.bat` から3ツールを対話的に選択 |
| ローカル/SSH切替 | Windows ローカルとLinux SSH の両対応 |
| テンプレート自動配備 | `CLAUDE.md` / `AGENTS.md` / `copilot-instructions.md` を自動配置 |
| ClaudeOS カーネル | 37体のエージェント + 67スキル + 35コマンド + フック |
| MCP ヘルスチェック | `McpHealthCheck.psm1` で4サーバーの起動・接続・状態診断 |
| Agent Teams ランタイム | `AgentTeams.psm1` でタスク分析→Team自動構成→可視化 |
| PTY Bridge | SSH経由のClaude Code操作を堅牢にサポート |
| 一元設定 | `config/config.json` で全ツールを統一管理 |
| 診断ツール | `Test-AllTools.ps1` で環境を一括チェック |
| CI/CD | GitHub Actions による自動テスト (Pester) |

---

## クイックスタート

### 前提条件

**Windows 側:**
- Windows 10/11
- PowerShell 5.1 以上
- Node.js 18 以上
- Git / SSH クライアント

**Linux 側（SSH 起動時）:**
- `claude` / `codex` / `copilot` を実行できる環境
- SSH 鍵認証

### セットアップ

```cmd
git clone <repository-url> D:\ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New
cd D:\ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New
copy config\config.json.template config\config.json
```

`config/config.json` を環境に合わせて編集:

```json
{
  "projectsDir": "D:\\",
  "sshProjectsDir": "Z:\\",
  "linuxHost": "your-linux-host",
  "linuxBase": "/mnt/LinuxHDD",
  "tools": { "defaultTool": "claude" }
}
```

ツールインストール:

```powershell
npm install -g @anthropic-ai/claude-code
npm install -g @openai/codex
npm install -g @githubnext/github-copilot-cli
```

---

## 使用方法

### 対話メニュー

```cmd
start.bat
```

| メニュー | 説明 |
|----------|------|
| `S1` | Claude Code を SSH 起動 |
| `S2` | Codex CLI を SSH 起動 |
| `S3` | GitHub Copilot CLI を SSH 起動 |
| `L1` | Claude Code をローカル起動 |
| `L2` | Codex CLI をローカル起動 |
| `L3` | GitHub Copilot CLI をローカル起動 |
| `5` | ツール確認・診断 |
| `6` | ドライブマッピング診断 |
| `7` | Windows Terminal セットアップ |
| `8` | MCP ヘルスチェック |
| `9` | Agent Teams ランタイム |

### PowerShell から直接起動

```powershell
.\scripts\main\Start-All.ps1
.\scripts\main\Start-ClaudeCode.ps1 -Project "my-project"
.\scripts\main\Start-CodexCLI.ps1 -Project "my-project"
.\scripts\main\Start-CopilotCLI.ps1 -Project "my-project" -Local
```

---

## ClaudeOS v6 自律開発システム

### ループ構成

| ループ | 時間 | 責務 | 禁止事項 |
|--------|------|------|----------|
| Monitor | 30m | 要件・設計・状態確認、タスク分解 | 実装・修復 |
| Development | 2h | 設計、実装、テスト追加 | main 直接 push |
| Verify | 1h | test/lint/build/CI確認、STABLE判定 | 未テスト merge |
| Improvement | 1h | リファクタリング、docs更新 | 破壊的変更 |

### STABLE 判定条件

| 条件 | 必須 |
|------|------|
| install | SUCCESS |
| lint | SUCCESS |
| test | SUCCESS |
| build | SUCCESS |
| CI | SUCCESS |
| error count | 0 |
| security issue | 0 |

### Agent Teams

| ロール | 責務 |
|--------|------|
| CTO | 優先順位判断、時間制御 |
| Architect | アーキテクチャ設計、責務分離 |
| Developer | 実装、修正、修復 |
| Reviewer | コード品質、差分確認 |
| QA | テスト、回帰確認 |
| Security | 脆弱性・権限確認 |
| DevOps | CI/CD・PR・Deploy制御 |

### CI Manager（自動修復）

- CI失敗は必ず失敗として扱う（成功偽装禁止）
- 修復は最小差分、1修復 = 1仮説
- 最大15回リトライ、同一エラー3回で Blocked

---

## 設定の要点

| キー | 説明 |
|------|------|
| `projectsDir` | ローカル参照用のプロジェクトルート |
| `sshProjectsDir` | SSH 実行時に Windows 側で参照する共有ドライブ |
| `linuxHost` | SSH 接続先 |
| `linuxBase` | Linux 側のプロジェクトルート |
| `tools.defaultTool` | `Start-All.ps1` のデフォルトツール |

---

## ディレクトリ構成

```text
config/              設定テンプレートと設定ドキュメント
docs/                利用ガイド（共通/Claude/Codex/Copilot）
scripts/lib/         共通モジュール (7 modules)
  Config.psm1          設定管理
  LauncherCommon.psm1  起動共通処理
  MenuCommon.psm1      メニュー共通処理
  SSHHelper.psm1       SSH接続ヘルパー
  ErrorHandler.psm1    エラーハンドリング
  McpHealthCheck.psm1  MCPヘルスチェック [NEW]
  AgentTeams.psm1      Agent Teamsランタイム [NEW]
scripts/main/        起動スクリプト
scripts/helpers/     PTY bridge 等のヘルパー
scripts/templates/   各ツール向けテンプレート
scripts/test/        診断スクリプト
scripts/tools/       TASKS同期・バックログ管理
tests/               Pester テスト (8 files)
Claude/              ClaudeOS 互換ポリシー群
Codex/               Codex AGENTS.md
.claude/claudeos/    ClaudeOS カーネル（204ファイル）
.codex/              Codex 設定
.github/             Copilot 設定 / CI ワークフロー
```

---

## 診断とテスト

```powershell
# 全ツール診断
.\scripts\test\Test-AllTools.ps1

# MCP ヘルスチェック
.\scripts\test\Test-McpHealth.ps1

# Agent Teams ランタイム診断
.\scripts\test\Test-AgentTeams.ps1

# JSON 出力
.\scripts\test\Test-AllTools.ps1 -OutputFormat Json
.\scripts\test\Test-McpHealth.ps1 -OutputFormat Json
.\scripts\test\Test-AgentTeams.ps1 -OutputFormat Json -Task "Fix CI build"

# Pester テスト
Invoke-Pester .\tests\
```

---

## ドキュメント

| カテゴリ | ファイル |
|----------|----------|
| 共通 | `docs/common/01_はじめに.md` 〜 `13_グローバル設定適用設計.md` |
| Claude | `docs/claude/01_概要.md` 〜 `05_ベストプラクティス.md` |
| Codex | `docs/codex/01_概要.md` 〜 `04_ベストプラクティス.md` |
| Copilot | `docs/copilot/01_概要.md` 〜 `04_ベストプラクティス.md` |

---

## 開発ロードマップ (v3.0.0)

| フェーズ | 期間 | 主な目標 |
|----------|------|----------|
| Phase 1 (現在) | 2026 Q2 | P1完了、モジュール基盤確立 |
| Phase 2 | 2026 Q3 | Worktree並列開発、Issue自動生成 |
| Phase 3 | 2026 Q4 | Agent Teams可視化UI、ダッシュボード |

---

## 注意事項

- `Claude Code` は設定上 `--dangerously-skip-permissions` を利用できます。開発環境専用です。
- API キーをソースに保存しないでください。
- SSH 実行では Linux 側の `linuxBase` と Windows 側の共有パスが同じプロジェクト群を指す前提です。

## ライセンス

MIT License
