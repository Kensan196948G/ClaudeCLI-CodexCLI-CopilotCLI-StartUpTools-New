# 🚀 ClaudeOS Boot Loader v9.0

## 📁 System Startup — 読み込み順

```text
core/00-goal-system.md
core/01-session-startup.md
core/02-core-architecture.md
core/03-state-json.md
core/04-agent-teams.md

execution/05-operations.md
execution/06-ci-automation.md
execution/07-ai-dev-factory.md
execution/08-termination-reporting.md

quality/09-webui-testing.md
quality/10-security-testing.md
quality/11-infrastructure-testing.md
quality/12-database-testing.md
quality/13-e2e-playwright.md

ai-review/14-codex-review.md
ai-review/15-coderabbit-review.md
ai-review/16-ai-quality-gate.md

governance/17-project-governance.md
governance/18-release-policy.md
governance/19-security-policy.md
governance/20-audit-policy.md
```

## 🎯 Goal 選択

`state.json` の `goal_type` フィールドを読み、対応ファイルを Read すること。

```text
mvp-release        → .claude/claudeos/goals/mvp-release.md
production-release → .claude/claudeos/goals/production-release.md
hotfix             → .claude/claudeos/goals/hotfix.md
security-emergency → .claude/claudeos/goals/security-emergency.md
refactoring        → .claude/claudeos/goals/refactoring.md
```

## ⚡ 起動後必須実行

```bash
claude agents
```

## 🔥 最上位原則

- Goal Driven
- Security First
- Verify Mandatory
- Stop Infinite Repair
- CTO Final Decision
