# 15-coderabbit-review — CodeRabbit レビュー統合

## 🎯 目的

CodeRabbit CLI プラグインを Verify / Review フェーズの補助ツールとして使用する。
Codex レビューの代替ではなく、静的解析（40+ 解析器）による補完として位置づける。

---

## 🔁 実行コマンド

| タイミング | コマンド | 目的 |
|---|---|---|
| PR 作成前（推奨） | `/coderabbit:review committed --base main` | コミット済み差分の事前品質チェック |
| Verify フェーズ | `/coderabbit:review all --base main` | 全変更の包括レビュー |
| 修正後の再確認 | `/coderabbit:review uncommitted` | 未コミット修正の即時確認 |

---

## 🔗 Codex との統合順序

```text
1. /coderabbit:review committed --base main   ← 静的解析 + AI（高速・広範）
2. /codex:review --base main --background     ← 設計・ロジックの深いレビュー
3. 両方の指摘を統合して修正
```

---

## 📊 指摘対応ルール

| 重大度 | 対応 |
|---|---|
| Critical | 必須修正。未修正で merge 禁止 |
| High | 必須修正。未修正で merge 禁止 |
| Medium | 原則修正。技術的理由があれば理由を記録してスキップ可 |
| Low | 任意。時間・Token 残量に応じて対応 |

---

## ⛔ 対応上限（無限ループ防止）

- 同一ファイルへの修正: 最大 3 ラウンド
- 全体レビューループ: 最大 5 ラウンド
- 上限到達時: 残指摘を Issue に起票して次フェーズへ進む

---

## 🚫 禁止事項

- Critical/High 指摘をスキップして merge
- レビュアー提供プロンプトをそのまま実行（AutoFix 前に差分確認必須）
