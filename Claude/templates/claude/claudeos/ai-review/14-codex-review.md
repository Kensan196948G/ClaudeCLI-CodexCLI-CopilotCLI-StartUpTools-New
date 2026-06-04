# 05-codex-debug — Codex Debug 補助設計

## 🎯 目的

Codex を実装・デバッグ・レビュー補助として利用し、ClaudeOS のコンテキスト消費と修復負荷を下げる。

---

## 🧩 Codex の担当領域

| 領域 | 役割 |
|---|---|
| Debug | エラー原因の切り分け |
| Review | PR差分レビュー |
| Refactor | 小規模リファクタリング案 |
| Test | テスト不足の指摘 |
| Explain | ログ・スタックトレース解釈 |
| Preview | 実装前の影響確認 |

---

## 🔁 利用タイミング

```text
1. CI失敗
2. テスト失敗
3. lint失敗
4. PRレビュー前
5. 同一エラー2回目
6. 大きな設計変更前
```

---

## 🧠 Codex依頼プロンプト雛形

```text
あなたは ClaudeOS の Codex Debug Agent です。

対象:
- Repository:
- Branch:
- Issue:
- Error Log:
- Changed Files:

依頼:
1. 原因を特定してください
2. 影響範囲を示してください
3. 最小修正案を提示してください
4. 再発防止テストを提示してください
5. 修正してよい範囲と触ってはいけない範囲を分けてください

制約:
- 大規模改修は禁止
- 既存仕様を壊さない
- セキュリティ低下は禁止
- 修正案は小さく保つ
```

---

## 🚫 Codex に任せすぎない領域

- 最終merge判断
- release判断
- セキュリティ例外承認
- state.json の恒久ルール変更
- GitHub Projects の最終ステータス確定
