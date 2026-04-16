# SSH リモート実行ガイド

Windows から Linux ホストへ SSH 接続し、リモート側で AI CLI を起動するための現行ガイドです。

---

## 概要

現行構成 (v3.1.0) では、Windows 側の起動スクリプトが SSH 経由で Linux 上に bash スクリプトを転送し、対象プロジェクトのディレクトリで `claude` を実行します。さらに **Linux crontab に登録した週次自動起動** や、**メニュー 13 経由の Statusline 一括適用** も同じ SSH 経路を再利用します。

主に使う設定:

| キー | 用途 |
|------|------|
| `sshProjectsDir` | Windows 側の共有ドライブ |
| `projectsDirUnc` | 共有ドライブの UNC パス |
| `linuxHost` | SSH 接続先 |
| `linuxBase` | Linux 側のプロジェクトルート |
| `cron.launcherPath` | `~/.claudeos/cron-launcher.sh` (v3.1.0 新設) |
| `statusline.sourceSettingsPath` | Windows 側 `~/.claude/settings.json` (v3.1.0 新設) |

---

## 実行イメージ

```text
Windows
├─ Start-Menu.ps1
│   ├─ S1/L1: Start-ClaudeCode.ps1
│   ├─ 12   : New-CronSchedule.ps1   (v3.1.0 🆕)
│   └─ 13   : Set-Statusline.ps1     (v3.1.0 🆕)
│
└─ ↓ SSH (PTY bridge / 単発コマンド / crontab パイプ)
Linux
├─ /home/kensan/Projects/{project} で claude を起動
├─ /home/kensan/.claudeos/cron-launcher.sh   (Cron から起動)
├─ /home/kensan/.claudeos/sessions/*.json    (セッション状態)
├─ /home/kensan/.claudeos/logs/cron-*.log    (cron ログ)
└─ ~/.claude/settings.json                   (statusLine 同期先)
```

> v3.1.0 で Codex CLI / GitHub Copilot CLI の SSH 起動メニュー (S2/S3/L2/L3) は廃止されました。

---

## v3.1.0 新機能: Linux crontab 連携

メニュー 12 から登録した cron エントリは以下の形式で `crontab -l` に追記されます:

```cron
# CLAUDEOS:8f3a1c2e project=my-app duration=300 created=2026-04-16T21:00:00
0 21 * * 0 /home/kensan/.claudeos/cron-launcher.sh my-app 300 >> /home/kensan/.claudeos/logs/cron-$(date +\%Y\%m\%d-\%H\%M\%S).log 2>&1
```

- `# CLAUDEOS:<uuid>` コメント行が ID。CronManager.psm1 はこのアンカで自分のエントリだけを安全に Add/Remove
- `cron-launcher.sh` が `timeout 300m claude` を実行し、`session.json` を作成・更新
- 終了時 (timeout / 正常完了 / エラー) の status は `completed` / `failed` のいずれかで記録

### 手動で crontab を確認する

```bash
ssh 192.168.0.185 "crontab -l | grep -A1 CLAUDEOS"
```

### cron 起動セッションの監視

Cron 起動の場合でも、Windows Terminal で `Show-SessionInfoTab.ps1 -SessionId <sid>` を手動実行すれば、リモートで実行中のセッションを情報タブで監視できます (Linux 側 session.json を SCP / SMB マウント等で参照する必要あり)。

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

`sshProjectsDir` を `"auto"` にすると、空きドライブレターを自動検出して `projectsDirUnc` をマッピングします。
重複を避けて P → Q → R → ... の順に探索し、すべて使用済みの場合は Z → D の逆順でフォールバックします。
マッピングに失敗した場合は SSH 直接接続に自動フォールバックします。

```json
{
  "sshProjectsDir": "auto",
  "projectsDirUnc": "\\\\192.168.0.185\\Projects"
}
```

特定のドライブレターを使いたい場合は明示的に指定できます:

```json
{
  "sshProjectsDir": "P:\\",
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
