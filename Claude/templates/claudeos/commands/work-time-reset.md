---
description: 現セッションの最大作業時間をデフォルト (300 分) に戻す
---

# /work-time-reset — 作業時間リセット

デフォルト 300 分 (5 時間) に戻します。内部的には `/work-time-set 300` と等価です。

```bash
bash /home/kensan/.claudeos/cron-cli.sh worktime-reset --session "$CLAUDE_SESSION_ID"
```

`cron-cli.sh` が無い場合は `/work-time-set 300` を呼び出してください。
