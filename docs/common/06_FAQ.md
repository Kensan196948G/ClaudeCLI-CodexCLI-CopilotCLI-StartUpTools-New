# よくある質問

---

## Q0. v3.1.0 で何が変わりましたか？

- メニュー S2/S3/L2/L3 (Codex CLI / GitHub Copilot CLI 起動) が **削除** されました
- メニュー **12. Cron 登録・編集・削除** と **13. Statusline 設定** が新設されました
- S1/L1 起動時に Windows Terminal で **Session Info タブ** が自動生成されるようになりました
- ClaudeCode 内から **Slash command** (`/cron-register`, `/work-time-set` など) で対話制御できるようになりました

詳細は [CHANGELOG.md](../../CHANGELOG.md) の v3.1.0 セクションを参照してください。

---

## Q1. Windows だけで使えますか？

はい。`L1` または `-Local` を使えば Windows ローカルで Claude Code を起動できます。SSH は Linux 上で動かしたい場合だけ必要です。**Cron 機能 (メニュー 12)** は Linux crontab を使うため SSH 接続が前提です。

---

## Q2. Codex CLI / Copilot CLI は使えなくなりましたか？

**起動メニュー (S2/S3/L2/L3) は v3.1.0 で削除されました。** ただし以下の点に注意してください:

- `Start-CodexCLI.ps1` / `Start-CopilotCLI.ps1` ファイル自体は残置されています
- `config.json` の `tools.codex.enabled = true` に戻し、旧 `Start-Menu.ps1` を参照すれば復活可能 (非推奨)
- **Codex によるコードレビュー** (`/codex:review`, `/codex:rescue`) は ClaudeCode 内の Slash command として **引き続き利用可能** です。これは別物です

---

## Q3. Claude Code は API キー必須ですか？

必須ではありません。サブスクリプション認証でも使えます。

- Claude Code: `claude` 起動後に `/login`
- API 利用時のみ環境変数 `ANTHROPIC_API_KEY` を設定

---

## Q3.1. Cron で起動した場合はどうやって認証されますか？

`cron-launcher.sh` は `claude` を非対話モードで起動するため、事前に Linux 側で `/login` 完了済み (認証情報がディスクに保存済み) または `ANTHROPIC_API_KEY` 環境変数の設定が必要です。

---

## Q3.2. Session Info タブは何秒間隔で更新されますか？

デフォルトは **1 秒間隔** です。`config.json` の `sessionTabs.pollIntervalSeconds` で変更可能。残り時間は `session.json` の `end_time_planned` と現在時刻の差分で計算するため、JSON 更新を待たずに秒単位で滑らかにカウントダウンします。

---

## Q3.3. `/work-time-set 240` で残り時間が即変わるのはなぜですか？

Slash command が `session.json` の `max_duration_minutes` を書き換え、`end_time_planned` も `start_time + 240 分` で再計算されるためです。情報タブは 1 秒 poll で `session.json` を読み直し、新しい終了予定時刻に基づいて残り時間を再計算します。

---

## Q4. プロジェクトはどこから選ばれますか？

- ローカル起動: `projectsDir`
- SSH 起動: `sshProjectsDir`

`-Project` を明示すれば選択をスキップできます。

---

## Q5. 共有ドライブが見えない場合は？

`projectsDirUnc` の設定と `test-drive-mapping.ps1` の結果を確認してください。

```powershell
.\scripts\test\test-drive-mapping.ps1
```

---

## Q6. どのツールから始めるべきですか？

- 実装とレビューをまとめて任せたい: Claude Code
- 軽快な CLI 支援がほしい: Codex CLI
- GitHub 操作支援がほしい: GitHub Copilot CLI

---

## Q7. tmux や DevTools は必須ですか？

いいえ。現行構成の標準フローでは必須ではありません。旧構成由来の説明は現在の標準運用ではありません。

---

## Q8. テストはありますか？

あります。現時点では Pester による共通モジュール中心のテストです。

```powershell
Invoke-Pester .\tests\
```
