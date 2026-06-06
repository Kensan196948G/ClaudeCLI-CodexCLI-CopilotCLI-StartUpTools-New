# 01-session-startup — セッション開始・復元ルール (v9.0)

## 🎯 目的

ClaudeOS v9.0 起動時に、`/goal` 設定・前回状態・GitHub・CI・Project の状況を必ず復元し、CTO の動的判断材料を整える。

---

## ✅ セッション開始時の必須処理

```text
1. state.json 読込（前回ゴール・KPI・blocked_issues 復元）
2. 週次フェーズ算出（start_date から自動計算）
3. GitHub Issues / Projects 状態取得
4. CI 状態取得（gh run list --limit 5）
5. /goal 設定（達成条件 + or stop after N turns）
6. Agent View 起動（claude agents）
7. CTO 優先順位評価 → 最初のアクション決定
8. 本セッションの作業方針を出力
```

---

## 🎯 /goal 設定


/goal 
#"MVP Release Candidate を完成させる。完了条件: 全主要画面正常動作・API疎通成功・認証認可正常・DB CRUD成功・CI成功・Critical/High脆弱性ゼロ・E2Eテスト成功・README/運用手順完成・Docker起動成功・ローカル環境再現可能。停止条件: MVP完成・CI成功・リリース条件達成・修復ループ上限到達"
/goal "
MVP Release Candidate を完成させる。

優先順位：
1. 動作
2. 安定性
3. セキュリティ
4. 保守性
5. UI改善

完了条件：
- 全主要機能動作
- CI成功
- Critical/High脆弱性ゼロ
- Docker再現成功（docker-compose.yml がある場合のみ）
- README完成
- E2E成功

制約：
- 5時間以内
- 修復ループ最大5回
- 過剰リファクタ禁止
- 新技術導入禁止
- アーキテクチャ全面変更禁止

停止条件：
- MVP完成
- リリース条件達成
- 修復上限到達
"


---

## 📤 必須出力

セッション開始時は必ず以下を出力する。

```text
[Session Restore Report v9.0]

Project:
- name:
- start_date:
- release_deadline:
- week_phase: Week N → Build/Quality/Stabilize/Release

/goal:
- current: (設定中の条件)
- status: active / not set

GitHub:
- open_issues:
- active_prs:
- latest_ci_status:

KPI:
- ci_success_rate:
- test_pass_rate:
- security_critical:
- blocker_count:

blocked_issues: (あれば列挙)

CTO Decision:
- 優先アクション: (§5 CTO優先順位テーブルに基づく)
- reason:
```

---

## 🚦 CTO 優先順位（v9.0 Dynamic Orchestration）

| 優先度 | 状態 | 行動 |
|---|---|---|
| 1 | Security Critical | 即時対応（Agent Teams パターン B） |
| 2 | CI 失敗中 | 原因分析 + 最小差分修復 |
| 3 | Blocker Issue | 解除 |
| 4 | /goal 直結 Issue | 実装（パターン A 検討） |
| 5 | 検証不足 | 品質強化（パターン B） |
| 6 | 改善 | 余裕がある場合のみ |
