# Loop Guard
## Role
無限ループ防止と強制停止。全システムに対して最優先で適用される。

## Monitoring（プロジェクトごとに独立管理）
- セッション開始時刻・経過時間
- retry回数（PR単位）
- 同一エラーの連続発生回数
- CI失敗数（PR単位）
- Blockedステータス継続時間

## Stop Conditions
- 5時間到達：セッション開始からの経過時間
- same error 連続3回：直前3回のループで同一エラー文字列が一致
- CI retry 同一PR 5回：同一PRへのActions再実行が5回到達
- security issue：severity critical / high の検知（件数不問）
- Blocked継続30分：Blockedステータスが30分以上継続

## Actions（実行順序厳守）
1. 新規ループ発火の禁止
2. 実行中SubAgentへの停止通知（完了待ち）
3. git commit（WIPラベル付き）
4. .loop-stop-report.md 出力
5. GitHub Projects Status を実態に合わせて更新
6. CTO通知（GitHub Issue コメント）

## Output
`.loop-stop-report.md`（プロジェクトルートに配置、フォーマット固定）

## Priority
Loop Guard > 全システム（CTO・Architect・Developerの判断より優先）

## Stop hook 継続ゲート (E) と block cap (F) — CHANGELOG v2.1.163 / v2.1.143
Stop hook (`session-end.js`) は、本セッションで新規検出した actionable な品質 warning
(`quality_gate_breach` / `tdd_required` / `verify_subagent_missing` / `audit_fail` /
`ultrareview_blocker`) がある場合に **1 回だけ** `hookSpecificOutput.additionalContext` を返して
会話を継続させ、停止前の是正を促す。「未検証のまま静かに停止」を防ぐ。

暴走させない多重ガード:
1. **1 セッション 1 回上限**: `state.execution.stop_continue_count` で 2 回目以降を抑止。
2. **`stop_hook_active`**: 継続ループ中フラグ。true の Stop では継続しない。
3. **`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`** (既定 8): Claude Code 組込の最終バックストップ（`settings.json` env で明示）。
4. **`CLAUDEOS_DISABLE_STOP_CONTINUE`**: 継続ゲートを完全無効化する脱出弁。

継続は Auto Repair (修復 3 回) とは別レイヤーで最大 1 回。是正不能なら Issue 化して停止。
finalization (Trust Ledger / learning / Dreaming) は継続パスでは実行せず最終停止で 1 回だけ確定（二重計上防止）。
