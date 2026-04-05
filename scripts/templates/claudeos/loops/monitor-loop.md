# Monitor Loop

## Role
システム状態と品質の監視。

---

## Checks

- CI status
- test results
- lint
- typecheck
- security warnings
- token usage
- retry count

---

## Trigger

- ループ開始時
- 各フェーズ終了後
- CI実行後

---

## Actions

- 状態収集
- 異常検知
- リスク判定

---

## Output

`.loop-monitor-report.md`

---

## Next

- 異常あり → Verify Loop
- 正常 → Build Loop

---

## 5h Rule

- 状態ログを必ず保存