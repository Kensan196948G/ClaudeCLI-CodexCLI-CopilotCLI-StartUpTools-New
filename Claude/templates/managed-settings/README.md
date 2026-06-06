# 🔒 Claude Code managed settings — バージョン下限の強制

ClaudeOS は Claude Code の特定バージョン以降の機能に依存します（例: `/goal` 2.1.139+、dynamic workflows 2.1.154+、reloadSkills/sessionTitle 2.1.152+）。古い Claude Code で起動すると**機能がサイレントに欠落**し、自律開発が静かに劣化します。

`requiredMinimumVersion` / `requiredMaximumVersion` は **managed settings 専用キー**（通常の `.claude/settings.json` では効きません）で、範囲外バージョンでの起動を**起動時に拒否**します（`claude update` / `claude install` / `claude doctor` は範囲外でも動くので復旧可能）。

## 📌 推奨値

| キー | 推奨 | 根拠 |
|---|---|---|
| `requiredMinimumVersion` | `"2.1.154"` | ClaudeOS が依存する最新機能 floor（dynamic workflows）。/goal・Agent Teams・skills・reloadSkills を全て内包 |
| `requiredMaximumVersion` | 未設定（任意） | 上限を固定したい場合のみ。`autoUpdatesChannel: latest` 運用なら通常不要 |

`managed-settings.json` をそのまま使うか、floor を運用方針に合わせて調整してください。

## 🚀 配置場所（OS 別）

| OS | 配置場所 |
|---|---|
| 🐧 **Linux**（実行機 192.168.0.185） | `/etc/claude-code/managed-settings.json`（または `/etc/claude-code/managed-settings.d/*.json` をアルファベット順マージ） |
| 🪟 **Windows**（開発機） | レジストリ `HKLM\SOFTWARE\Policies\ClaudeCode`（Group Policy） |
| 🍎 macOS | MDM plist `com.anthropic.claudecode` |

> ⚠️ managed settings は**システム/管理者権限**が必要です（`/etc` 書込・レジストリ）。リポジトリ内の `.claude/` には置けません。本テンプレは「正本」であり、実配置は人手（または構成管理）で行います。

## 🐧 Linux 実行機への適用手順（例）

```bash
# 192.168.0.185 上で（sudo 必要）
sudo mkdir -p /etc/claude-code
sudo cp Claude/templates/managed-settings/managed-settings.json /etc/claude-code/managed-settings.json
# 検証: 範囲外バージョンだと起動拒否される
claude doctor
```

## ✅ 適用後の確認

- `claude doctor` で managed settings が認識されているか確認。
- floor 未満の Claude Code で `claude` を起動 → 起動拒否＋承認バージョン案内が出れば成功。
- cron（`cron-launcher.sh`）経由の自律セッションにも自動適用される（同一 OS 上の managed settings は全 claude 起動に効く）。

## 関連

- 設定キー一覧: `Claude/templates/claude/CLAUDE.md` §「新設定キー」
- 出典: Claude Code CHANGELOG v2.1.163 / 公式 settings ドキュメント（managed settings）
