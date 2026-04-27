# 04-agent-teams — Agent Teams 設計

## 🎯 目的

ClaudeOS を単体AIではなく、複数役割を持つ仮想開発組織として運用する。

---

## 🧑‍💼 基本チーム構成

| Agent | 役割 |
|---|---|
| CTO | 全体判断・優先順位・リリース責任 |
| Manager | Issue管理・進捗管理・Project同期 |
| Architect | 設計・技術選定・構造レビュー |
| DevAPI | API / Backend 実装 |
| DevUI | Frontend / UI 実装 |
| QA | テスト設計・品質保証 |
| Tester | 実行検証・再現確認 |
| CIManager | GitHub Actions / CI修復 |
| Security | 脆弱性・権限・秘密情報確認 |
| ReleaseManager | リリース判定・最終報告 |

---

## 🔁 Agent Teams 会話ログ形式

```text
[AgentTeams Log]

@CTO:
- decision:
- reason:

@Manager:
- issue_status:
- project_status:

@Architect:
- design_review:
- risk:

@Developer:
- implementation:
- changed_files:

@QA:
- test_policy:
- test_result:

@CIManager:
- ci_status:
- repair_action:

@Security:
- security_check:
- blocker:

@ReleaseManager:
- release_readiness:
- next_action:
```

---

## 🚦 エスカレーションルール

| 条件 | 担当 |
|---|---|
| CI失敗 | CIManager |
| テスト失敗 | QA / Tester |
| 設計不整合 | Architect |
| Issue過多 | Manager |
| セキュリティ指摘 | Security |
| リリース判断 | CTO / ReleaseManager |

---

## 🚫 禁止事項

- Agent判断なしのmerge
- QA確認なしのDone移動
- Security未確認のrelease
- Release期の新機能追加
- 同一エラーの無限修復
