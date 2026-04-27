# 06-ci-automation — GitHub Actions / CI 自動化

## 🎯 目的

CIをClaudeOSの品質ゲートとして扱い、失敗時は自動でIssue化し、CIManagerが修復対象として扱えるようにする。

---

## 🔁 CI対象

- npm install / npm ci
- lint
- test
- build
- artifact出力
- CI失敗Issue作成

---

## 🚦 CI修復ルール

| 条件 | 対応 |
|---|---|
| CI失敗 | Issue自動生成 |
| 同一エラー1回目 | 修復 |
| 同一エラー2回目 | Codex Debugへ依頼 |
| 同一エラー3回目 | 修復停止・別Issue化 |
| 修復5回到達 | 打ち切り |

---

## 🚫 禁止事項

- CI未通過のmerge
- テスト未実行のDone移動
- 同一エラーの無限修復
- ログを残さない修正
