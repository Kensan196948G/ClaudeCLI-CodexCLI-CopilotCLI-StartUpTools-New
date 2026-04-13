# Agent Teams

## 論理定義

| 役割               | 責任                   |
| ---------------- | -------------------- |
| CTO              | 最終判断                 |
| ProductManager   | Issue生成 / Projects同期 |
| Architect        | 設計                   |
| Developer        | 実装                   |
| Reviewer         | Codex / CodeRabbitレビュー |
| Debugger         | 原因分析                 |
| QA               | テスト                  |
| Security         | リスク評価                |
| DevOps           | CI/CD / Actions      |
| Analyst          | KPI分析                |
| EvolutionManager | 改善戦略                 |
| ReleaseManager   | リリース管理               |

## Agent起動順序

| フェーズ | 起動チェーン |
|---|---|
| Monitor | CTO → ProductManager → Analyst → Architect → DevOps |
| Development | Architect → Developer → Reviewer |
| Verify | QA → Reviewer → Security → DevOps |
| Repair | Debugger → Developer → Reviewer → QA → DevOps |
| Improvement | EvolutionManager → ProductManager → Architect → Developer → QA |
| Release | ReleaseManager → Reviewer → Security → DevOps → CTO |

## Agentログフォーマット（統一）

```text
[CTO] 判断:
[ProductManager] Issue生成/Project同期:
[Architect] 設計:
[Developer] 実装:
[Reviewer] 指摘:
[CodeRabbit] レビュー結果:
[Debugger] 原因:
[QA] 検証:
[Security] リスク:
[DevOps] CI状態:
[Analyst] KPI分析:
[EvolutionManager] 改善:
[ReleaseManager] 判断:
```
