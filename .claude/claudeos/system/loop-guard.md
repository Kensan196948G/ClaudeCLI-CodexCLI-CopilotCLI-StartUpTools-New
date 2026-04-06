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
