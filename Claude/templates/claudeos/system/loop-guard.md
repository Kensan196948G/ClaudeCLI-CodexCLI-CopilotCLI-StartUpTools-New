# Loop Guard

## 役割

誤判定や無限ループを防ぐ。

## 停止条件

- 同じ失敗を3回繰り返した
- CI 修復を5回以上試した
- security critical issue を検出した
- 5時間上限に近づいた

## 重要

ループ判定は時間ではなく主作業内容で行う。

## Stop hook 継続ゲート (E) と block cap (F) — CHANGELOG v2.1.163 / v2.1.143

Stop hook (`session-end.js`) は、本セッションで新規検出した actionable な品質 warning
(`quality_gate_breach` / `tdd_required` / `verify_subagent_missing` / `audit_fail` /
`ultrareview_blocker`) がある場合に **1 回だけ** `hookSpecificOutput.additionalContext` を返して
会話を継続させ、停止前の是正を促す。「未検証のまま静かに停止」を防ぐ。

### 暴走させない多重ガード

1. **1 セッション 1 回上限**: `state.execution.stop_continue_count` で 2 回目以降の継続を抑止。
2. **`stop_hook_active`**: Claude Code が継続ループ中に渡す標準フラグ。true の Stop では継続しない。
3. **`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`** (既定 8): Claude Code 組込の最終バックストップ。
   Stop hook の連続継続がこの回数に達すると強制停止する (`settings.json` の `env` で明示・調整可)。
4. **`CLAUDEOS_DISABLE_STOP_CONTINUE`**: 設定すると継続ゲートを完全に無効化する脱出弁。

### §12 / 本ガードとの関係

- 継続は Auto Repair (修復 3 回) とは別レイヤー。継続は**最大 1 回**なので無限ループにならない。
- 是正不能なら Issue 化して停止する。
- finalization (Trust Ledger 加算 / learning / Dreaming spawn) は継続パスでは実行せず、最終停止で
  1 回だけ確定する (二重計上防止)。
