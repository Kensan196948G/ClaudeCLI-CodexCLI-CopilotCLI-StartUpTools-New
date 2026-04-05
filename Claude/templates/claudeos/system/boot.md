# ClaudeOS Boot Sequence

## Role
ClaudeOSの起動と全体初期化。

---

## Boot Flow

1. Environment Check
   - OS / Shell / Git / Node / Python

2. Project Detection
   - CLAUDE.md / repo構造確認

3. Memory Restore
   - Memory MCP / Claude-mem

4. System Init
   - Loop Guard起動
   - Token Budget初期化
   - Project Switch決定

5. Executive Init
   - AI CTO起動
   - Strategy Engine起動

6. Management Init
   - Backlog Manager
   - Scrum Master

7. Agent Init
   - Agent Teams起動
   - SubAgent割当

8. Loop Engine Start
   - Monitor / Build / Verify / Improve

9. Dashboard表示
   - startup-dashboard.md

---

## Startup Checks

- Git状態確認
- CI設定確認
- 未処理Issue確認
- Token残量確認

---

## Output

- 起動ログ
- 初期Project状態

---

## 5h Rule

- 起動時刻記録