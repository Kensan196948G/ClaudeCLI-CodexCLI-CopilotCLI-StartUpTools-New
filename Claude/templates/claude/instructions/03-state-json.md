# 03-state-json — state.json 仕様

## 🎯 目的

state.json は ClaudeOS の意思決定・継続判断・失敗学習・進捗復元の中核ファイルである。

---

## 🧠 state.json 完全版

```json
{
  "project": {
    "name": "project-name",
    "start_date": "2026-01-01",
    "release_deadline": "2026-07-01"
  },
  "phase": {
    "current": "build",
    "week": 1
  },
  "kpi": {
    "ci_success_rate": 0.0,
    "test_pass_rate": 0.0,
    "review_blocker_count": 0,
    "security_issue_count": 0
  },
  "execution": {
    "max_duration_minutes": 300,
    "loop_count": 0,
    "max_loops": 3,
    "ci_retry_limit": 5,
    "same_error_limit": 2
  },
  "status": {
    "current_phase": "monitor",
    "stable": false
  },
  "priority": {
    "score": 0
  },
  "learning": {
    "failure_patterns": [],
    "success_patterns": []
  }
}
```

---

## 🔄 更新タイミング

| タイミング | 更新内容 |
|---|---|
| セッション開始 | current_phase / week / KPI |
| Monitor完了 | Issue / PR / CI状態 |
| Development完了 | 実装対象 / 変更内容 |
| Verify完了 | test_pass_rate / CI状態 |
| Improvement完了 | 改善内容 / 学習 |
| 終了時 | loop_count / stable / next_action |

---

## 🧬 学習ルール

### failure_patterns

以下を記録する。

- 同じCIエラー
- 同じテスト失敗
- 同じlintエラー
- 設計ミス
- セキュリティ指摘

### success_patterns

以下を記録する。

- 修復成功手順
- 安定した実装パターン
- 再利用可能なテスト
- 有効だったIssue分割
- 有効だったレビュー観点

---

## 🚨 安全ルール

- state.json が壊れている場合は、復元用 state.backup.json を作成する
- JSON構文エラー時は自動修復せず、修復Issueを作成する
- release_deadline は原則変更禁止
- loop_count は実行ごとに必ず増加させる
