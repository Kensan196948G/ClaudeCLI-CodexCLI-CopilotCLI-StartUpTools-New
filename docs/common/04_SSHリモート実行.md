# SSH リモート実行ガイド

Windows から Linux ホストへ SSH 接続し、リモート側で AI CLI を起動するための現行ガイドです。

---

## 概要

現行構成では、Windows 側の起動スクリプトが SSH 経由で Linux 上に bash スクリプトを転送し、対象プロジェクトのディレクトリで `claude`、`codex`、`copilot --yolo` を実行します。

主に使う設定:

| キー | 用途 |
|------|------|
| `sshProjectsDir` | Windows 側の共有ドライブ |
| `projectsDirUnc` | 共有ドライブの UNC パス |
| `linuxHost` | SSH 接続先 |
| `linuxBase` | Linux 側のプロジェクトルート |

---

## 実行イメージ

```text
Windows
├─ Start-Menu.ps1 / Start-All.ps1
├─ Start-ClaudeCode.ps1
├─ Start-CodexCLI.ps1
└─ Start-CopilotCLI.ps1
       ↓ SSH
Linux
└─ /home/kensan/Projects/{project} で各 CLI を起動
```

---

## SSH 鍵設定

```powershell
ssh-keygen -t ed25519 -C "your-email@example.com" -f "$env:USERPROFILE\.ssh\id_ed25519"
```

公開鍵を Linux 側へ登録し、パスワードなしで接続できるようにしてください。

接続確認:

```powershell
ssh your-linux-host "echo OK"
```

---

## `~/.ssh/config` 例

```sshconfig
Host mydev
    HostName 192.168.0.185
    User myusername
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

`config.json` 側:

```json
{
  "linuxHost": "mydev",
  "linuxBase": "/home/kensan/Projects"
}
```

---

## 共有ドライブ

SSH 起動では、Windows 側で `sshProjectsDir` に共有ドライブが見えている前提です。たとえば:

```json
{
  "sshProjectsDir": "Z:\\",
  "projectsDirUnc": "\\\\192.168.0.185\\Projects"
}
```

診断:

```powershell
.\scripts\test\test-drive-mapping.ps1
```

---

## Linux 側の前提

- `claude` と `codex` が実行可能
- `gh` と `gh-copilot` を使う場合は `gh auth login` 済み
- `linuxBase` 配下に対象プロジェクトが存在
- `base64` と `bash` が利用可能

---

## DryRun

SSH 実行内容を確認したい場合:

```powershell
.\scripts\main\Start-ClaudeCode.ps1 -Project "my-app" -DryRun
.\scripts\main\Start-CodexCLI.ps1 -Project "my-app" -DryRun
.\scripts\main\Start-CopilotCLI.ps1 -Project "my-app" -DryRun
```

---

## 注意

- 現行構成は旧 DevTools ポートフォワーディングや tmux ダッシュボードを標準前提にしていません。
- SSH 実行は、Windows 側と Linux 側で同じプロジェクト群が見えている前提です。
