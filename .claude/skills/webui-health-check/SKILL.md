---
name: webui-health-check
description: Mission Control WebUI の健全性を確認し、問題があれば Issue を起票する
---

# WebUI 健全性チェックスキル

Dashboard WebUI (`http://localhost:3737`) の稼働状態と設定を確認します。

## 実行手順

```bash
# 1. サーバー稼働確認
curl -s http://localhost:3737/api/health | python -m json.tool

# 2. システム健全性確認
curl -s http://localhost:3737/api/system-health | python -m json.tool

# 3. 認証設定確認
# authEnabled: false の場合は DASHBOARD_PASSWORD 環境変数設定を推奨
```

## 重要チェック項目

| チェック | 状態 | 対応 |
|---|---|---|
| `authEnabled` | ⚠️ false | `DASHBOARD_PASSWORD` または `config.json.dashboardAuth` を設定 |
| `packageJsonMissing` | ⚠️ true | `package.json` を作成 |
| `claudeSkillsMissing` | ⚠️ true | `.claude/skills/` を作成 |
| `dashboardTaskState` | ✅ Ready | タスクスケジューラー登録済み |
