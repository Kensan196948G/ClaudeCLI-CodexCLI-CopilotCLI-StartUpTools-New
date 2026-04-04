# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools

Windows から `Claude Code`、`Codex CLI`、`GitHub Copilot CLI` を統一的に起動するためのスタートアップツールです。ローカル起動と SSH リモート起動の両方に対応し、設定・診断・ガイドをこのリポジトリに集約しています。

## 対応ツール

| ツール | 提供元 | 主な用途 |
|--------|--------|---------|
| Claude Code | Anthropic | 大規模なコード修正、レビュー、実装支援 |
| Codex CLI | OpenAI | ターミナル中心のコード生成、シェル支援 |
| GitHub Copilot CLI | GitHub | `copilot --yolo` によるシェル・GitHub 操作支援 |

## 主な機能

- `start.bat` から対話メニューで起動
- ツール別の専用起動スクリプトを提供
- Windows ローカル起動と Linux への SSH 起動を切り替え可能
- `config/config.json` による一元設定
- `scripts/test/Test-AllTools.ps1` による診断
- プロジェクトごとに `CLAUDE.md`、`AGENTS.md`、`.github/copilot-instructions.md` を自動配備
- `config/config.json.template` を正本とした設定運用

## クイックスタート

### 前提条件

Windows 側:
- Windows 10/11
- PowerShell 5.1 以上
- Node.js 18 以上
- Git
- SSH クライアント
- GitHub Copilot CLI

Linux 側（SSH 起動時）:
- `claude` / `codex` / `copilot` を実行できる環境
- SSH 鍵認証
- プロジェクトディレクトリへのアクセス

### セットアップ

1. リポジトリをクローン

```cmd
git clone <repository-url> D:\ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New
cd D:\ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New
```

2. 設定ファイルを作成

```cmd
copy config\config.json.template config\config.json
```

3. `config/config.json` を環境に合わせて編集

```json
{
  "projectsDir": "D:\\",
  "sshProjectsDir": "Z:\\",
  "projectsDirUnc": "\\\\your-linux-host\\LinuxHDD",
  "linuxHost": "your-linux-host",
  "linuxBase": "/mnt/LinuxHDD",
  "tools": {
    "defaultTool": "claude"
  }
}
```

4. 各ツールをインストール

```powershell
npm install -g @anthropic-ai/claude-code
npm install -g @openai/codex
npm install -g @githubnext/github-copilot-cli
```

5. 必要に応じて認証

```powershell
# Claude Code
claude
# 起動後に /login

# Codex CLI
codex --login

# GitHub Copilot CLI
copilot auth
```

6. 診断を実行

```powershell
.\scripts\test\Test-AllTools.ps1
.\scripts\test\Test-AllTools.ps1 -OutputFormat Json
pwsh -NoProfile -File .\scripts\test\Test-McpRuntime.ps1 -OutputFormat Json
```

## 使用方法

### 対話メニュー

```cmd
start.bat
```

現行メニュー:
- `S1` Claude Code を SSH 起動
- `S2` Codex CLI を SSH 起動
- `S3` GitHub Copilot CLI を SSH 起動
- `L1` Claude Code をローカル起動
- `L2` Codex CLI をローカル起動
- `L3` GitHub Copilot CLI をローカル起動
- `5` ツール確認・診断
- `6` ドライブマッピング診断
- `7` Windows Terminal セットアップ

`5` の診断では、設定スキーマ、CLI コマンド、認証状態、共有パス、起動例をまとめて確認します。

### PowerShell から直接起動

```powershell
.\scripts\main\Start-All.ps1
.\scripts\main\Start-ClaudeCode.ps1 -Project "my-project"
.\scripts\main\Start-CodexCLI.ps1 -Project "my-project"
.\scripts\main\Start-CopilotCLI.ps1 -Project "my-project" -Local
```

### 非対話モード

```powershell
.\scripts\main\Start-ClaudeCode.ps1 -Project "backend-api" -NonInteractive
.\scripts\main\Start-CodexCLI.ps1 -Project "backend-api" -NonInteractive
.\scripts\main\Start-CopilotCLI.ps1 -Project "backend-api" -NonInteractive -Local
```

## アーキテクチャ

```text
Windows
├─ start.bat
├─ scripts/main/Start-Menu.ps1
├─ scripts/main/Start-All.ps1
└─ scripts/main/Start-{ClaudeCode,CodexCLI,CopilotCLI}.ps1
   ├─ ローカル起動: projectsDir 配下で実行
   └─ SSH 起動: linuxHost / linuxBase 上で実行
```

## 設定の要点

| キー | 説明 |
|------|------|
| `projectsDir` | ローカル参照用のプロジェクトルート |
| `sshProjectsDir` | SSH 実行時に Windows 側で参照する共有ドライブ |
| `projectsDirUnc` | 共有ドライブの UNC パス |
| `linuxHost` | SSH 接続先 |
| `linuxBase` | Linux 側のプロジェクトルート |
| `tools.defaultTool` | `Start-All.ps1` のデフォルトツール |

Copilot は `copilot --yolo` を前提にしています。

設定運用の詳細は [config/README.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/config/README.md) と [docs/common/07_設定運用ガイド.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/docs/common/07_設定運用ガイド.md) を参照してください。

```json
"copilot": {
  "enabled": true,
  "displayName": "GitHub Copilot CLI",
  "command": "copilot",
  "args": ["--yolo"],
  "installCommand": "npm install -g @githubnext/github-copilot-cli",
  "checkCommand": "copilot --version"
}
```

## ディレクトリ構成

```text
config/           設定テンプレートと設定ドキュメント
docs/             利用ガイド
scripts/lib/      共通モジュール
scripts/main/     起動スクリプト
scripts/setup/    セットアップ補助
scripts/templates 各ツール向けテンプレート
scripts/test/     診断スクリプト
tests/            Pester テスト
Claude/           ClaudeOS 互換ポリシー群
```

## ドキュメント

- `docs/common/01_はじめに.md`
- `docs/common/02_ツール比較ガイド.md`
- `docs/common/03_Windowsセットアップ.md`
- `docs/common/04_SSHリモート実行.md`
- `docs/common/05_トラブルシューティング.md`
- `docs/common/06_FAQ.md`
- `docs/common/08_AgentTeams対応表.md`
- `docs/common/09_CIと実機ヘルスチェック.md`
- `docs/common/10_区切りサマリ.md`
- `docs/claude/01_概要.md`
- `docs/claude/03_使い方.md`
- `docs/codex/01_概要.md`
- `docs/copilot/01_概要.md`

## 診断とテスト

```powershell
.\scripts\test\Test-AllTools.ps1
.\scripts\test\test-drive-mapping.ps1
Invoke-Pester .\tests\
```

機械可読な診断結果が必要な場合:

```powershell
.\scripts\test\Test-AllTools.ps1 -OutputFormat Json
.\scripts\test\test-drive-mapping.ps1 -OutputFormat Json
```

`Test-AllTools.ps1 -OutputFormat Json` の主な出力項目:

```json
{
  "schemaVersion": "1.0.0",
  "configPath": "config path",
  "configExists": true,
  "configValid": true,
  "schemaValid": true,
  "errors": [],
  "common": [],
  "tools": [],
  "mcp": {
    "configured": false,
    "configPath": "",
    "servers": [],
    "summary": "..."
  },
  "paths": [],
  "examples": [],
  "summary": {
    "ok": true,
    "message": "..."
  }
}
```

`test-drive-mapping.ps1 -OutputFormat Json` では `recommendation`、`repairAdvice`、`remapCommand`、`netUseIssue` も返します。Windows Terminal セットアップでは `-FontFace`、`-UseAcrylic`、`-ThemeJsonPath` を指定できます。診断スキーマ本体は [test-all-tools-report.schema.json](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/docs/common/schemas/test-all-tools-report.schema.json) です。

MCP を使う場合は `.mcp.json` の各 server 定義に `healthCommand` を追加できます。利用可能な環境では `Test-AllTools.ps1` が疎通確認まで実行し、利用不能な環境では `health_command_unavailable` または `unavailable` を返します。

実機で startup / shutdown / health の runtime probe まで回す場合は、CI ではなく次を使います。

```powershell
pwsh -NoProfile -File .\scripts\test\Test-McpRuntime.ps1
pwsh -NoProfile -File .\scripts\test\Test-McpRuntime.ps1 -OutputFormat Json
```

2026年3月13日に `pwsh -NoProfile -File .\scripts\test\Test-McpRuntime.ps1 -OutputFormat Json` を実行した結果、`config/config.json` の読込は成功し、`.mcp.json` が存在しないため `mcp.configured = false` を返しました。現状は `MCP 設定未作成` の状態です。

CI と実機チェックの境界は [09_CIと実機ヘルスチェック.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/docs/common/09_CIと実機ヘルスチェック.md) を参照してください。

## 注意事項

- `Claude Code` は設定上 `--dangerously-skip-permissions` を利用できます。開発環境専用です。
- API キーをソースに保存しないでください。
- SSH 実行では Linux 側の `linuxBase` と Windows 側の共有パスが同じプロジェクト群を指す前提です。

## ライセンス

MIT License
