# Verify Loop

## Role
品質検証とCI確認。

---

## Checks

- code review
- unit tests
- integration tests
- lint
- build
- CI stability

---

## Trigger

- Build後
- 修正後

---

## Actions

- テスト実行
- CI確認
- 品質評価

---

## Output

`.loop-verify-report.md`

---

## Next

- 成功 → Improve Loop
- 失敗 → CI Manager / Auto Repair

---

## STABLE Check

以下を評価：

- test success
- CI success
- lint success
- build success
- error 0
- security issue 0

---

## 5h Rule

- 未完でも評価を残す