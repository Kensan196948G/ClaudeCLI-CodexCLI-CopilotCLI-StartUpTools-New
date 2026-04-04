# CI Auto Repair

Automatic correction of CI failures.

# CI Auto Repair

## Role
CI失敗の自動修復を行う。

---

## Repair Strategy

優先順位：

1. 設定ミス修正
2. 依存関係修正
3. テスト修正
4. コード修正
5. 設計見直し

---

## Repair Rules

- 最小変更で修正
- 変更は必ずcommit単位
- 影響範囲を限定する

---

## Loop Control（重要）

- 同一修正を繰り返さない
- 無限ループ検知時は停止

---

## Escalation

以下でエスカレーション：

- retry > 7 → Architect
- retry > 10 → CTO

---

## 8h Rule

- 8時間到達で修復停止
- 状態を必ず記録
- 次サイクルへ引継ぎ