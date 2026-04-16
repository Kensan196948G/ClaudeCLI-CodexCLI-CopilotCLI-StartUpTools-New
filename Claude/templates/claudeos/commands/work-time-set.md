---
description: 現セッションの最大作業時間 (max_duration_minutes) を変更する
---

# /work-time-set — 作業時間の変更

引数:
- `$1 = <minutes>` → その分数に設定（例: `/work-time-set 240` で 4 時間）

実行:

```bash
NEW_MIN="${1:-300}"
SESSION_FILE="$HOME/.claudeos/sessions/${CLAUDE_SESSION_ID}.json"

if [ ! -f "$SESSION_FILE" ]; then
  echo "[ERROR] session.json が見つかりません: $SESSION_FILE" >&2
  exit 1
fi

python3 - "$SESSION_FILE" "$NEW_MIN" <<'PYEOF'
import json, sys
from datetime import datetime, timedelta
path = sys.argv[1]
new_min = int(sys.argv[2])
with open(path) as f:
    s = json.load(f)
start = datetime.fromisoformat(s['start_time'].replace('Z', '+00:00'))
s['max_duration_minutes'] = new_min
s['end_time_planned'] = (start + timedelta(minutes=new_min)).isoformat()
s['last_updated'] = datetime.now().astimezone().isoformat()
with open(path, 'w') as f:
    json.dump(s, f, ensure_ascii=False, indent=2)
print(f'[OK] max_duration_minutes = {new_min}, end_time_planned 再計算済')
PYEOF
```

情報タブは 1 秒 poll なので即時に表示が追従します。
