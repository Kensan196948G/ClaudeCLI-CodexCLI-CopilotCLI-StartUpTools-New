# 07-ai-dev-factory — AI Dev Factory

## 🎯 目的

ClaudeOS が backlog / TODO / CI / KPI / Review から自動的にIssue候補を生成し、開発対象を枯渇させない。

---

## 🏭 Issue自動生成条件

- CI失敗
- KPI未達
- テスト不足
- セキュリティ指摘
- backlog.md の未処理項目
- TODOコメントの蓄積
- docs/roadmap.md との差分
- 既存Issueのブロッカー

---

## 📝 Issueテンプレート

```text
Title: [P1] 問題概要

Reason:
CI failure / KPI gap / test gap / security risk

Context:
- 発生箇所:
- 関連ファイル:
- 関連Issue:
- 関連PR:

Acceptance:
- 再現可能
- 修正可能
- テスト可能
- CI通過
- 影響範囲が説明されている

Priority:
P1 / P2 / P3

Owner:
ClaudeOS / CIManager / QA / Security
```

---

## 📊 優先順位

| 優先度 | 条件 |
|---|---|
| P1 | Security / CI停止 / Release阻害 |
| P2 | テスト不足 / 品質低下 |
| P3 | 改善 / リファクタリング |
| P4 | 将来案 / 調査 |

---

## 🚫 Release期の制約

Release期に生成された新機能Issueは原則Backlogへ回す。

ただし、以下は例外。

- Security修正
- Release阻害バグ
- データ破損リスク
- ビルド不能
