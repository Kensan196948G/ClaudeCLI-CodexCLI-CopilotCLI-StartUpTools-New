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
