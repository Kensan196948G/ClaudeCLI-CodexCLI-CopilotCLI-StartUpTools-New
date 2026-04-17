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

`reports/.loop-monitor-report.md`

> 配布先プロジェクトで `reports/` ディレクトリが未作成の場合、本レポートの
> 書き出し前に `New-Item -ItemType Directory reports -Force` で作成すること。

---

## Next

- 異常あり → Verify Loop
- 正常 → Build Loop

---

## 5h Rule

- 状態ログを必ず保存