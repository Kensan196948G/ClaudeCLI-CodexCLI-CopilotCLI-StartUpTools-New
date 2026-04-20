# Agent Teams

## 論理定義

| 役割               | 責任                   |
| ---------------- | -------------------- |
| CTO              | 最終判断                 |
| ProductManager   | Issue生成 / Projects同期 |
| Architect        | 設計                   |
| Developer        | 実装                   |
| Reviewer         | Codexレビュー / CodeRabbitレビュー |
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

v3.2.54 からアイコン + 英語名 / 日本語名併記に統一する:

```text
[👔 CTO / 最高技術責任者] 判断:
[📋 ProductManager / プロダクトマネージャー] Issue生成/Project同期:
[🏛️ Architect / アーキテクト] 設計:
[💻 Developer / デベロッパー] 実装:
[🔍 Reviewer / レビュアー] 指摘:
[🐛 Debugger / デバッガー] 原因:
[🧪 QA / 品質保証] 検証:
[🔒 Security / セキュリティ] リスク:
[⚙️ DevOps / 運用基盤] CI状態:
[📊 Analyst / アナリスト] KPI分析:
[🧬 EvolutionManager / 進化マネージャー] 改善:
[🚀 ReleaseManager / リリースマネージャー] 判断:
[🐰 CodeRabbit] レビュー結果: Critical=N High=N Medium=N Low=N
```

- アイコンは省略禁止 (Windows Terminal + pwsh 7 で描画確認済)
- 英語名 / 日本語名の両方を `/` で併記すること
- サブエージェント委任・結果統合もすべて上記形式で表示 (内部完結禁止)
