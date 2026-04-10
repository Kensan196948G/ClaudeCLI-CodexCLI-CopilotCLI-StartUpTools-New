# state.json スキーマ・優先順位AI

## state.json（優先順位AI 完全版）

```json
{
  "project": {
    "name": "sample-project",
    "mode": "autonomous"
  },
  "goal": {
    "title": "自律開発最適化",
    "description": "品質と安定性を維持しながら継続的に改善する"
  },
  "kpi": {
    "success_rate_target": 0.9,
    "test_pass_rate_target": 0.95,
    "review_blocker_target": 0,
    "security_blocker_target": 0,
    "ci_stability_target": 0.95
  },
  "execution": {
    "max_duration_minutes": 300,
    "cooldown_minutes_min": 5,
    "cooldown_minutes_max": 15,
    "retry_limit_ci": 15,
    "same_root_cause_limit": 3
  },
  "automation": {
    "auto_issue_generation": true,
    "auto_project_sync": true,
    "self_evolution": true,
    "auto_priority_scoring": true,
    "auto_repair": true
  },
  "priority": {
    "weights": {
      "security": 100,
      "ci_failure": 90,
      "data_risk": 85,
      "test_failure": 75,
      "review_findings": 70,
      "kpi_gap": 65,
      "technical_debt": 40,
      "minor_ux": 20
    },
    "current_top_reason": "ci_failure"
  },
  "learning": {
    "failure_patterns": [],
    "success_patterns": [],
    "blocked_patterns": [],
    "preferred_fix_order": ["security", "ci", "test", "review", "refactor"]
  },
  "github": {
    "default_branch": "main",
    "require_pr": true,
    "require_codex_review": true,
    "require_actions_success": true,
    "project_sync_enabled": true
  },
  "status": {
    "stable": false,
    "blocked": false,
    "current_phase": "monitor",
    "last_updated": "YYYY-MM-DDTHH:MM:SSZ"
  }
}
```

## 優先順位AI

### 判定原則

優先順位は感覚で決めず、`state.json.priority.weights` に基づいてスコア計算する。

### 判定対象

- Security blocker
- CI failure
- build failure
- test failure
- review findings
- data impact
- KPI gap
- technical debt
- UX / docs / minor tasks

### 判定ルール

- 最大スコアの項目を最優先とする
- 同点の場合: `security > ci > data > test > review > kpi > debt > ux`
- P1 未解決中は P3 を凍結する
- 進行中 Issue より高優先 Issue が出たら切替可能
