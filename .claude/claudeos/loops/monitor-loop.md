# Monitor Loop

## Role
システム状態と品質の監視。**観測専用** (判定は Verify, 実装は Build の責務)。

---

## 最初に行うこと (Resume Protocol)

セッション冒頭 or ループ冒頭で、以下を **先頭に** 出力する:

1. **条件付き実行**: `.loop-handoff-report.md` が **存在する場合のみ** 以下を行う
   - 「前回の停止理由」を読み上げる
   - 「次の第一手」を宣言する
   - `state.json.execution.last_stop_reason` を参照する
2. **新規セッション (handoff 不在) の場合**: Resume Protocol をスキップし、
   「前回停止理由: N/A (新規セッション)」と 1 行だけ出力する。
   架空の停止理由を捏造してはならない (`state.json.execution.last_stop_reason` には何も書かない)
3. その後で通常の Monitor チェックに進む

---

## Checks

- CI status
- test results
- lint
- typecheck
- security warnings
- token usage
- retry count
- no_progress_streak
- same_diff_streak

---

## Trigger

- ループ開始時
- 各フェーズ終了後
- CI 実行後

---

## Actions

- 状態収集
- 異常検知
- **リスク検知** (判定・結論は書かない。「要検証フラグ」を state.json に立てて Verify へ引き渡すのみ)

---

## Output

`.loop-monitor-report.md` — **観測専用**。判定結論は書かない。

---

## Next

- 異常あり → Verify Loop
- 正常 → Build Loop

---

## 5h Rule

- 状態ログを必ず保存
- 残時間 < 30 分なら Improvement スキップ宣言
