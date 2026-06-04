# 02-core-architecture — ClaudeOS v9.0 Core Architecture

## 🧠 システム概要

ClaudeOS v9.0 は AI を単なる開発補助ではなく、AI 開発組織そのものとして統合動作させる。
`/goal` コマンドで目標を設定し、CTO に全権委任する。Agent Teams で並列に動き、Agent View で監視する。

```
止まらない。ただし暴走しない。
必ず検証する。Goal 達成後は適切に終了する。
```

---

## 🎯 統合対象

- `/goal` 駆動の自律継続開発（v2.1.139+ 公式機能）
- Agent Teams による並列協調開発（パターン A/B/C）
- Agent View（`claude agents`）によるセッション監視
- 完全自律開発（CTO 委任）
- 5 時間セッション最適化
- KPI 連動動的判断
- 6 か月フェーズ制御
- state.json 意思決定 AI
- GitHub Actions 自動修復
- GitHub Projects 完全同期
- AI Dev Factory
- Codex / CodeRabbit Review 補助
- 終了報告と引き継ぎ

---

## 📆 6 か月フェーズ制御

```text
現在週 = (today - start_date) / 7
```

| 週 | フェーズ | 主目的 | Agent Teams |
|---|---|---|---|
| 1–8 | Build | 機能開発・基盤構築 | パターン A 多用 |
| 9–16 | Quality | 品質強化・テスト拡充 | パターン B 多用 |
| 17–20 | Stabilize | 安定化・バグ収束 | パターン B |
| 21–24 | Release | リリース準備・検証完了 | パターン B + Audit |

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

## 🔁 実行フロー（v9.0 動的判断）

```text
/goal 設定 → state.json Read → CTO 優先順位評価
→ 最適行動選択（Fix/Build/Verify/Improve）
→ Agent Teams spawn（必要時）
→ /goal 達成判定（Haiku）→ 次ターン or 終了
```

フォールバック: `Monitor → Development → Verify → Improvement`

---

## 📈 KPI 制御（v9.0）

| 状態 | score | 行動 |
|---|---|---|
| security_critical > 0 | +5 | Security 最優先 |
| CI 失敗 | +3 | Verify / Repair |
| test_pass_rate < 0.8 | +2 | QA 強化 |
| blocker_count > 0 | +3 | Blocker 解除 |

score ≥ 5 → 強制継続 / ≥ 3 → 継続 / ≥ 1 → 軽量 / 0 → 終了

---

## 🚫 強制ルール

- Release 期は新機能禁止
- Security は最優先
- 未検証 merge 禁止
- 同一原因エラーは **2 回まで**（3 回目は Issue 化）
- CI 修復は最大 **3 回まで**
- CLAUDE.md / settings.json / hooks の自己書き換え禁止
- force push 禁止
