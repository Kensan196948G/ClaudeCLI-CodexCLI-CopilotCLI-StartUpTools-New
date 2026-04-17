---
description: Linux crontab に CLAUDEOS 週次自動起動エントリを登録する
---

# /cron-register — Cron エントリ登録

以下の手順で crontab を更新してください。

1. 現在のセッションの `$CLAUDE_PROJECT` を取得（未設定なら session.json から読む）
2. 引数が未指定なら対話で聞き取る:
   - 曜日 (`0-6`、複数可): `$1`
   - 時刻 (`HH:MM`): `$2`
   - 作業時間 (分、省略時 300): `$3`
3. Bash で以下を実行:

```bash
bash /home/kensan/.claudeos/cron-cli.sh register \
  --project "${CLAUDE_PROJECT}" \
  --day "$1" \
  --time "$2" \
  --duration "${3:-300}"
```

4. 実行結果（ID と cron 式）をユーザーへ報告

`cron-cli.sh` が未配置の場合は、先に `/home/kensan/.claudeos/cron-launcher.sh` と合わせて
スタートアップツール経由で配置されているか確認してください。

## v3.2.0 — HTML メールレポート連携

登録した cron エントリは、終了時に `~/.claudeos/report-and-mail.py` 経由で HTML レポート
メールを送信します(`CLAUDEOS_EMAIL_ENABLED=1` で有効化、既定 off)。

メール送信を有効化する場合、次の追加準備をユーザーに案内してください:

1. `~/.env-claudeos` (chmod 600) に `CLAUDEOS_SMTP_USER` / `CLAUDEOS_SMTP_PASS` /
   `CLAUDEOS_EMAIL_ENABLED=1` を配置
2. `cron-launcher.sh` 冒頭で `source ~/.env-claudeos` していることを確認
3. dry-run で HTML プレビュー → 実機テスト送信で受信確認

詳細は `docs/common/16_HTMLメールレポート設定.md` を参照。
