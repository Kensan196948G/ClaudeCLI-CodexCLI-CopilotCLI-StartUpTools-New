# TASKS

このファイルは `手動管理セクション` と `自動抽出セクション` に分かれます。

- 手動管理: 人が直接追加・編集する backlog
- 自動抽出: `docs/common/08_AgentTeams対応表.md` の `未実装機能` から `Sync-AgentTeamsBacklog.ps1` が同期する項目

## Manual Backlog

1. [DONE] [Priority:P1][Owner:Ops][Source:CI] 初期 CI 構築・安定化 (obsolete — CI 安定稼働中)
2. [DONE] [Priority:P1][Owner:Architect][Source:Manual] Agent Teams ランタイム起動・multi-agent 自動割当 (PR #30)
3. [DONE] [Priority:P1][Owner:Ops][Source:Manual] MCP サーバーヘルスチェック統合 (PR #29)
4. [DONE] [Priority:P1][Owner:Developer][Source:GitHub#32] Worktree Manager 実装 (PR #37)
5. [DONE] [Priority:P1][Owner:Developer][Source:GitHub#33] Issue/Backlog 自動生成 (PR #38)
6. [DONE] [Priority:P2][Owner:Developer][Source:Manual] MCP/AgentTeams 機能強化 (PR #40)
7. [DONE] [Priority:P2][Owner:Developer][Source:Manual] Worktree 自動クリーンアップ (PR #41)
8. [DONE] [Priority:P2][Owner:DevOps][Source:Manual] Issue同期 CI/hooks 統合 (PR #45)
9. [DONE] [Priority:P2][Owner:Architect][Source:GitHub#49] Architecture Check Loop実装 (Phase 3)
10. [DONE] [Priority:P2][Owner:Architect][Source:GitHub#50] Self Evolution システム実装 (Phase 3)
11. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#128] PSAvoidAssignmentToAutomaticVariable 15件修正 (PR #129)
12. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#130] PSAvoidUsingEmptyCatchBlock 7件修正 (PR #131)
13. [DONE] [Priority:P3][Owner:Developer][Source:GitHub#127] Message Bus Phase 1 実装 (state.json message_bus セクション) (PR #132)
14. [Priority:P3][Owner:Developer][Source:GitHub#34] 開発ダッシュボード UI (Phase 3)
15. [Priority:P3][Owner:Ops][Source:GitHub#34] Memory MCP 永続化統合 (Phase 3)
16. [Priority:P3][Owner:Ops][Source:GitHub#34] Boot Sequence 完全自動化 (Phase 3)

## Auto Extracted From Agent Teams Matrix

1. [Priority:P2][Owner:Ops][Source:AgentTeamsMatrix] worktree ベースの並列ブランチ運用
2. [Priority:P2][Owner:ScrumMaster][Source:AgentTeamsMatrix] issue / backlog 自動生成
## GitHub Issues Sync

1. [Priority:P1][Owner:Unassigned][Source:GitHub#136] fix: PS1 ファイルの UTF-8 BOM なし問題（Windows PowerShell 5.1 ParseException）

