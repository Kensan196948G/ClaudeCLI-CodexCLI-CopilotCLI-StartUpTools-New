# 01-session-startup — セッション開始・復元ルール

## 🎯 目的

ClaudeOS 起動時に、前回状態・GitHub・CI・Project の状況を必ず復元し、現在セッションの判断材料を整える。

---

## ✅ セッション開始時の必須処理

```text
1. state.json 読込
2. 前回フェーズ取得
3. 未完了Issue取得
4. GitHub Projects同期
5. CI状態取得
6. 現在週と現在フェーズを算出
7. KPI状態を確認
8. 本セッションの作業方針を出力
```

---

## 📤 必須出力

セッション開始時は必ず以下を出力する。

```text
[Session Restore Report]

Project:
- name:
- start_date:
- release_deadline:

Phase:
- current:
- week:

GitHub:
- open_issues:
- active_prs:
- latest_ci_status:

KPI:
- ci_success_rate:
- test_pass_rate:
- review_blocker_count:
- security_issue_count:

Decision:
- continue / light / verify-only / terminate
- reason:
```

---

## 🚦 初期判断ルール

| 条件 | 判断 |
|---|---|
| security_issue_count > 0 | Security最優先 |
| CI失敗あり | Verify / Repair 優先 |
| 未完了Issueあり | Development対象に追加 |
| PR未検証 | Verify優先 |
| KPIすべて正常 | 軽量確認または終了 |
