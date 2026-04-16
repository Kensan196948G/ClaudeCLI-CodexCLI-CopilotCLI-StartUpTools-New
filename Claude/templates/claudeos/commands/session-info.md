---
description: 現セッションの session.json を整形表示する
---

# /session-info — セッション情報

```bash
SESSION_FILE="$HOME/.claudeos/sessions/${CLAUDE_SESSION_ID}.json"
if [ ! -f "$SESSION_FILE" ]; then
  echo "session 情報が見つかりません。手動起動（トリガ=manual）の場合は Windows 側の state/sessions を確認してください。"
  exit 0
fi
if command -v jq >/dev/null 2>&1; then
  jq . "$SESSION_FILE"
else
  cat "$SESSION_FILE"
fi
```

表示後、残り時間と status から「このセッションがあとどれくらい走るか」をユーザーに分かりやすく要約してください。
