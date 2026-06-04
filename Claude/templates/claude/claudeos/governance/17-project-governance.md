# 17-project-governance — プロジェクトガバナンス

## 🎯 目的

Issue 駆動開発・PR 必須・CI ゲートによりプロジェクトの健全性を維持する。

---

## 📋 Issue 駆動開発

- Issue なし作業禁止
- 重複 Issue 禁止
- P1 未解決なら P3 抑制

| レベル | 対象 |
|---|---|
| P1 | CI / セキュリティ / データ影響 |
| P2 | 品質 / UX / テスト |
| P3 | 軽微改善 |

---

## 🔁 GitHub Projects 状態遷移

```text
Inbox → Backlog → Ready → Design → Development → Verify → Deploy Gate → Done / Blocked
```

- セッション開始・終了時、各ループ終了時に更新
- 接続不可なら「未接続」または「不明」と明記

---

## 📖 Git / GitHub ルール

- main 直接 push 禁止
- branch または WorkTree 必須
- PR 必須（Draft 可）
- CI 成功のみ merge 許可

### PR 本文の最低限

- 変更内容
- テスト結果
- 影響範囲
- 残課題

---

## 🌿 WorkTree 運用

向いている場面:
- 1 Issue = 1 WorkTree
- 複数機能の並列開発

不要な場面:
- 1 ファイルの小修正
- ドキュメント更新のみ

---

## 📖 README 更新基準

以下のいずれかが変わったら更新する:
- 利用者が触る機能
- セットアップ手順
- アーキテクチャ
- 品質ゲート
