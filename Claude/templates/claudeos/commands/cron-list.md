---
description: 現在の CLAUDEOS Cron エントリ一覧を表示する
---

# /cron-list — Cron エントリ一覧

```bash
crontab -l 2>/dev/null | awk '
  /^# CLAUDEOS:/ { print; getline; print; print "" }
'
```

出力があれば表形式で整形してユーザーへ報告してください。
出力が無ければ「登録済みの CLAUDEOS エントリはありません」と伝えてください。
