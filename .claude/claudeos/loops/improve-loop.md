# Improve Loop

## Role
品質改善・最適化。

---

## Targets

- refactoring
- documentation
- naming
- error handling
- performance

---

## Trigger

- Verify成功後
- STABLE前

---

## Actions

- リファクタリング
- ドキュメント更新
- テスト改善

---

## Output

- improved code
- docs

---

## Next

- Monitor Loopへ戻る

---

## Stop-Doing Check（四半期点検）

Improve ループ開始時に以下を **先頭で** 判定する。期日未到来ならスキップ。

### 発火条件

```
state.json.improvement.stop_doing_review_date <= today
```

state.json が存在しない、または `improvement` ブロックが欠損している場合は **点検しない**。

### 実行手順（発火時のみ）

1. `git log --since=90.days.ago --name-only` で最近触れたファイルを列挙
2. `.claude/claudeos/` 配下の agents / skills / commands / hooks を Glob
3. `state.json.learning.usage_history` の呼び出し履歴と照合
4. 90 日以上未使用 + 猶予期間外の項目を `stale-candidate` として Issue 起票
5. 点検完了後 `state.json.improvement.stop_doing_review_date` を `+90d` に更新

---

## 5h Rule

- 改善内容を記録
