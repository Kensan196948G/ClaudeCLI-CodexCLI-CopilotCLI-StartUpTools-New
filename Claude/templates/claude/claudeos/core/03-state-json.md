# 03-state-json — state.json 仕様 (v9.0)

## 🎯 目的

state.json は ClaudeOS の意思決定・継続判断・失敗学習・進捗復元の中核ファイル。
v9.0 では `/goal` 条件・blocked_issues・learning パターンを正式に管理する。

---

## 🧠 state.json 完全版（v9.0）

```json
{
  "project": {
    "name": "project-name",
    "start_date": "2026-01-01",
    "release_deadline": "2026-07-01",
    "phase_mode": "development"
  },
  "goal": "Issue #XX-#YY 実装完了",
  "phase": "Monitor",
  "kpi": {
    "success_rate_target": 0.9,
    "ci_success_rate": 0.0,
    "test_pass_rate": 0.0,
    "security_critical": 0,
    "blocker_count": 0
  },
  "execution": {
    "max_duration_minutes": 300,
    "repair_count": 0,
    "max_repair": 3,
    "same_error_limit": 2,
    "loop_count": 0,
    "phase": "Monitor",
    "last_session_summary": ""
  },
  "automation": {
    "auto_issue_generation": true,
    "self_evolution": true
  },
  "stable": {
    "stable_achieved": false,
    "consecutive_success": 0
  },
  "completed_issues": [],
  "blocked_issues": [],
  "learning": {
    "failure_patterns": [],
    "success_patterns": []
  },
  "quality_gates": {
    "lint": { "warning_threshold": 10, "error_threshold": 0 },
    "coverage": { "line_min": 70, "changed_files_min": 80 }
  }
}
```

---

## 🔄 更新タイミング

| タイミング | 更新内容 |
|---|---|
| セッション開始 | Read（前回状態復元） |
| Issue 完了時 | `completed_issues` 追記 |
| CI 状態変化時 | `kpi.ci_success_rate` 更新 |
| ブロッカー発生時 | `blocked_issues` 追記 |
| Verify 完了時 | `kpi.test_pass_rate` / `stable` 更新 |
| 学習発生時 | `learning.failure_patterns` / `success_patterns` 追記 |
| セッション終了時 | Write（最終状態保存）|

毎ターン更新は不要。フェーズ遷移時のみ。

---

## 🧬 学習ルール（v9.0）

### learning.failure_patterns

以下を記録する（上限 20 件）：

- 同一エラーで 2 回詰まったケース
- blocked_issues の原因
- verify_subagent_missing 発生

### learning.success_patterns

以下を記録する（上限 20 件）：

- STABLE 達成時のセッションサマリー
- 修復成功手順
- 有効だった Agent Teams パターン

---

## 🚨 安全ルール

- state.json が壊れている場合は `state.backup.json` を作成する
- JSON 構文エラー時は自動修復せず、修復 Issue を作成する
- `release_deadline` は原則変更禁止
- `same_error_limit: 2` — 同一原因エラーは 2 回で Issue 化
