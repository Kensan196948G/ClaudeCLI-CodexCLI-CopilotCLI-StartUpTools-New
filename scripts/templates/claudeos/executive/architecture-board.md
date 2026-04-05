# Architecture Board

## Role
複数Agentによるアーキテクチャ審査機関。

---

## Members

- Architect
- DevAPI
- DevUI
- QA
- Security

---

## Trigger

以下で実行：

- PR作成時
- 大規模変更時
- CI failure多発
- STABLE判定前
- Architecture Refactor時

---

## Responsibilities

- design review
- system consistency
- dependency validation
- long-term architecture planning

---

## Actions

- 設計レビュー
- 構造整合確認
- 問題指摘
- 改善提案

---

## Output

- OK（承認）
- NG（修正要求）
- REFACTOR（再設計）

---

## Constraints

- 実装を止めすぎない
- 重要変更のみ強く介入

---

## 5h Rule

- 未完レビューでも結果を残す
- 次サイクルへ引継ぎ