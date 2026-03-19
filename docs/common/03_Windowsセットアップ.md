# Windows セットアップガイド

Windows 上でこのリポジトリを使うための最小セットアップ手順です。

---

## 前提条件

- Windows 10/11
- PowerShell 5.1 以上
- Node.js 18 以上
- Git
- SSH クライアント
- GitHub CLI `gh`

確認例:

```powershell
$PSVersionTable.PSVersion
node --version
npm --version
git --version
gh --version
ssh -V
```

---

## インストール

### Claude Code

```powershell
npm install -g @anthropic-ai/claude-code
claude --version
```

### Codex CLI

```powershell
npm install -g @openai/codex
codex --version
```

### GitHub Copilot CLI

```powershell
gh extension install github/gh-copilot
gh copilot --version
```

---

## 認証

### Claude Code

```powershell
claude
# 起動後に /login
```

### Codex CLI

```powershell
codex --login
```

### GitHub Copilot CLI

```powershell
gh auth login
gh auth status
```

---

## 設定ファイルの作成

```powershell
Copy-Item config\config.json.template config\config.json
```

最小例:

```json
{
  "version": "2.0.0",
  "projectsDir": "D:\\",
  "sshProjectsDir": "Z:\\",
  "projectsDirUnc": "\\\\192.168.0.185\\LinuxHDD",
  "linuxHost": "192.168.0.185",
  "linuxBase": "/mnt/LinuxHDD",
  "tools": {
    "defaultTool": "claude"
  }
}
```

---

## 起動確認

```cmd
start.bat
```

または:

```powershell
.\scripts\test\Test-AllTools.ps1
.\scripts\test\test-drive-mapping.ps1
```

診断では次の観点を確認します。

- `config/config.json` の存在とスキーマ
- `claude` / `codex` / `gh copilot` の利用可否
- `projectsDir` / `sshProjectsDir` / `projectsDirUnc` の参照可否
- 起動確認用の `-DryRun` コマンド例

JSON 出力が必要な場合:

```powershell
.\scripts\test\Test-AllTools.ps1 -OutputFormat Json
.\scripts\test\test-drive-mapping.ps1 -OutputFormat Json
```

---

## Windows Terminal

必要なら次を実行します。

```powershell
.\scripts\setup\setup-windows-terminal.ps1
```

このスクリプトは現行構成向けの Windows Terminal プロファイルを追加します。
追加されるプロファイル名は `AI CLI Startup` です。

既定プロファイル化と開始ディレクトリ指定もできます。

```powershell
.\scripts\setup\setup-windows-terminal.ps1 -SetAsDefault -StartingDirectory "D:\Work" -NonInteractive
```

テーマや文字サイズも指定できます。

```powershell
.\scripts\setup\setup-windows-terminal.ps1 -Theme "Campbell" -FontSize 20 -Opacity 90 -NonInteractive
```

```powershell
.\scripts\setup\setup-windows-terminal.ps1 -FontFace "Fira Code" -UseAcrylic:$false -NonInteractive
```

```powershell
.\scripts\setup\setup-windows-terminal.ps1 -ThemeJsonPath ".\my-theme.json" -NonInteractive
```

```powershell
.\scripts\setup\setup-windows-terminal.ps1 -ProfileName "AI CLI Main" -AdditionalProfileNames "AI CLI Ops","AI CLI QA" -NonInteractive
```
