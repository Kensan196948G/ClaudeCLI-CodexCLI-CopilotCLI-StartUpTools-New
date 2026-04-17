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
17. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v3.1.0 メニュー整理 (S2/S3/L2/L3 削除) + Cron 週次自動起動 + Session Info タブ + Statusline 全適用 + Slash commands 6 本 (PR #140)
18. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v8.2 Opus 4.7 最適化 + Anthropic 公式ベストプラクティス全反映 (Token 1.35x 補正 / Agent Teams 並列 spawn / /compact 事前発動 / task_budget / 1H cache / /ultrareview / PreCompact hook / /recap fallback / Push Notification / Effort 動的切替 / 文体 literalism 対応) (PR #142)
19. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v3.2.0 Cron HTML メールレポート (Visual Recap Mail) — report-and-mail.py 新規 / cron-launcher.sh finalize 連携 / config.json email セクション / SMTP 環境変数管理 / Gmail アプリパスワード手順ドキュメント (PR #143)
20. [DONE] [Priority:P1][Owner:Developer][Source:GitHub#147] v3.2.3 docs drift cleanup + state artifacts + hookify 検出強化 (PR #148)
21. [DONE] [Priority:P1][Owner:Developer][Source:GitHub#149] v3.2.4 repo rename docs 反映 — 22 ファイル / 55 箇所一括置換 (PR #150)
22. [DONE] [Priority:P1][Owner:Developer][Source:GitHub#151] v3.2.5 PSScriptAnalyzer 警告 10 件解消 — 7 ファイル修正 / CI Round 1 5 テスト失敗回収 / STABLE N=2 達成 (PR #152)
23. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#153] v3.2.6 PSUseApprovedVerbs 警告 9 件解消 — 8 ファイル / 9 関数改名 / STABLE N=2 達成 (PR #154)
24. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#155] v3.2.7 PSUseBOMForUnicodeEncodedFile 警告 35 件解消 — 35 ファイル UTF-8 BOM 追加 / STABLE N=2 達成 (PR #156)
25. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#157] v3.2.8 PSUseSingularNouns 警告 36 件解消 — 32 関数リネーム / 誤検知 4 件 SuppressMessageAttribute / STABLE N=2 達成 (PR #158)
26. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#160] v3.2.9 PSUseShouldProcessForStateChangingFunctions 警告 26 件解消 — 12 ファイル SuppressMessageAttribute / STABLE N=2 達成 (PR #161)
27. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.10 PSReviewUnusedParameter 警告 7 件解消 — 6 ファイル修正 (SuppressMessage 4件 / 実使用 1件 / Add-Member修正 1件) / STABLE N=2 達成
28. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.11 PSAvoidUsingPositionalParameters 警告解消 — 6 ファイル (Join-Path 6件 / Assert-Eq 12件 / Assert-Match 2件 / Write-BootStep 1件) 名前付き引数変換 (PR #163)
29. [Priority:P2][Owner:Developer][Source:Manual] v3.2.12 PSUseOutputTypeCorrectly 警告解消 — 7 ファイル 13 関数 [OutputType()] 追加

## Auto Extracted From Agent Teams Matrix

1. [Priority:P1][Owner:Ops][Source:AgentTeamsMatrix] Memory MCP 退避機能 (PreCompact hook 拡張、ClaudeOS v8.3 予定)
2. [Priority:P1][Owner:QA][Source:AgentTeamsMatrix] Verify 連動 ONBOARDING.md 自動再生成フック (Issue #100)
## GitHub Issues Sync

(No open issues)

























