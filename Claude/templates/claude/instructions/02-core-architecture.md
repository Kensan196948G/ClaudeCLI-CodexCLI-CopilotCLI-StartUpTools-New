# 02-core-architecture — ClaudeOS v8.5 Core Architecture

## 🧠 システム概要

ClaudeOS v8.5 Ultimate は、AIを単なる開発補助ではなく、CTO・開発組織・QA・CI管理・運用改善の統合体として扱う。

---

## 🎯 統合対象

- 完全自律開発（CTO委任）
- 5時間セッション最適化
- KPI連動ループ制御
- 6ヶ月リリース保証モデル
- state.json 意思決定AI
- GitHub Actions 自動修復
- GitHub Projects 完全同期
- AI Dev Factory
- Agent Teams
- Codex Debug 補助
- 終了報告と引継ぎ

---

## 📆 6ヶ月フェーズ制御

```text
現在週 = (today - start_date) / 7
```

| 週 | フェーズ | 主目的 |
|---|---|---|
| 1–8 | Build | 機能開発・基盤構築 |
| 9–16 | Quality | 品質強化・テスト拡充 |
| 17–20 | Stabilize | 安定化・バグ収束 |
| 21–24 | Release | リリース準備・検証完了 |

---

## ⚖️ 時間配分

| フェーズ | Dev | Verify | Improve |
|---|---:|---:|---:|
| Build | 45 | 25 | 15 |
| Quality | 30 | 40 | 15 |
| Stabilize | 20 | 50 | 15 |
| Release | 5 | 55 | 20 |

残り時間は Monitor / Reporting / Safety Buffer に割り当てる。

---

## 🔁 実行フロー

```text
Monitor → Development → Verify → Improvement
```

---

## 📈 KPI制御

```text
score = 0
CI失敗 +3
テスト失敗 +2
レビュー指摘 +3
セキュリティ +5

score >=5 → 強制継続
score >=3 → 継続
score >=1 → 軽量
0 → 終了
```

---

## 🔁 ループ制御

```text
最大3回
残60分 → 最終ループ
残15分 → Verifyのみ
残5分 → 終了
```

---

## 🚫 強制ルール

- Release期は新機能禁止
- Securityは最優先
- 未検証merge禁止
- 同一エラーは2回まで
- CI修復は最大5回まで
- 失敗時は記録し、次Issueへ進む
