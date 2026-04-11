# Improve Loop

## Role
品質改善・最適化。**条件付きループ** (必須ではない)。

---

## 起動条件 (必須ではない)

以下の **すべて** を満たした時のみ起動する。1 つでも欠けたらスキップ。

- [ ] Verify Loop が PASS
- [ ] 残時間 ≥ 30 分
- [ ] Token 使用率 < 70%
- [ ] `no_progress_streak == 0`
- [ ] モードが **full** (light モードでは Improvement をスキップする)

条件を満たさない場合は即座に Monitor Loop へ戻る。

---

## Targets

- refactoring (小さく)
- documentation 整備
- naming 改善
- error handling 整理
- performance (計測根拠がある場合のみ)

---

## 禁止事項

- 破壊的変更の無断実行
- テストカバレッジを下げるリファクタ
- 変更理由のないリネーム連鎖
- light モードでの起動

---

## Actions

- リファクタリング
- ドキュメント更新
- テスト改善

---

## Output

- improved code
- docs 差分

---

## Next

- Monitor Loop へ戻る

---

## 5h Rule

- 改善内容を記録
- 残時間 < 30 分で中断し、進行中の差分は WIP コミットを残す
