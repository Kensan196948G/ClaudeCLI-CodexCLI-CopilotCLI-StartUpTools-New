# Architecture Check Loop

## Role
構造の健全性を保証。

---

## Checks

- dependency structure
- module boundaries
- architecture rules
- layering consistency

---

## Trigger

- PR前
- STABLE判定前
- CI failure多発

---

## Actions

- 構造チェック
- 違反検出
- 改善提案

---

## Output

- architecture report

---

## Next

- OK → STABLE判定へ
- NG → Improve Loopへ

---

## 8h Rule

- 結果を必ず残す