# 09-termination-reporting — 終了処理・報告

## 🎯 目的

ClaudeOS セッション終了時に、作業結果・検証結果・未完了事項・次回引継ぎを明確に残す。

---

## 🧾 終了処理

```text
1. 変更差分確認
2. test / lint / build 結果確認
3. state.json更新
4. GitHub Project更新
5. 必要なら commit
6. 必要なら push
7. 必要なら PR作成
8. 終了報告作成
```

---

## ✅ commit / push / PR ルール

| 条件 | 対応 |
|---|---|
| 変更あり + 検証成功 | commit / push / PR |
| 変更あり + 検証失敗 | commit禁止、修復Issue作成 |
| docsのみ | 軽量検証後commit可 |
| Security未確認 | merge禁止 |
| CI未通過 | merge禁止 |

---

## 📤 終了報告テンプレート

```text
# ClaudeOS Session Report

## Summary
- Project:
- Phase:
- Week:
- Session Duration:
- Loop Count:

## Completed
- 
- 

## Changed Files
- 

## Verification
- lint:
- test:
- build:
- CI:

## KPI
- ci_success_rate:
- test_pass_rate:
- review_blocker_count:
- security_issue_count:
- score:

## GitHub
- Issues updated:
- PR created:
- Project status:

## Learning
### Failure Patterns
- 

### Success Patterns
- 

## Risks
- 

## Next Actions
1. 
2. 
3. 

## Final Decision
- stable: true / false
- next_session_mode: Monitor / Development / Verify / Improvement
```

---

## 🚫 終了時の禁止事項

- 検証失敗を隠す
- state.jsonを更新しない
- PRだけ作ってCI未確認
- Projectステータスを放置
- 次回アクションを残さない
