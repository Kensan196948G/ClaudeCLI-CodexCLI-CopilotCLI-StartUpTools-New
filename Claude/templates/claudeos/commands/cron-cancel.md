---
description: ID 指定または全指定で CLAUDEOS Cron エントリを解除する
---

# /cron-cancel — Cron エントリ解除

引数:
- `$1 = <id>` → その ID 1 件だけ削除
- `$1 = "all"` または未指定で確認後 → 全 CLAUDEOS エントリを削除

実行:

```bash
# ID 指定
if [ -n "$1" ] && [ "$1" != "all" ]; then
  bash /home/kensan/.claudeos/cron-cli.sh cancel --id "$1"
else
  bash /home/kensan/.claudeos/cron-cli.sh cancel --all
fi
```

実行後、`/cron-list` を実行して現状を確認してください。
