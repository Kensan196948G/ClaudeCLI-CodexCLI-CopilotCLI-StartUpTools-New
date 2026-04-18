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
29. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.12 PSUseOutputTypeCorrectly 警告解消 — 7 ファイル 13 関数 [OutputType()] 追加 / STABLE N=2 達成 (PR #164)
30. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.13 PSAvoidUsingPositionalParameters 残存 1 件解消 (Test-ArchitectureCheck.ps1) + CLAUDE.md v8.3 Auto mode / Response length calibration 追加 / STABLE N=2 達成 (PR #165)
31. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.14 PSProvideCommentHelp 警告 85 件解消 — 9 ファイル全関数に .SYNOPSIS 追加 / STABLE N=2 達成 (PR #167)
32. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v3.2.17 3タブ監視構成 + tmux UI 統合 — Watch-ClaudeLog.ps1 / Watch-SessionInfoSSH.ps1 新規 / cron-launcher.sh tmux TTY 実行化 / linuxUser config パラメータ化 / DateTimeOffset TZ 対応 (PR #168)
33. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v3.2.18 外部コードレビュー指摘 5 件対応 (Quick-wins) — reports/ 新設 (#17) / Claude/README.md 追加 (#6) / .codex/config.toml 簡略化 + profiles 復元 (#32) / README 標準コマンドセクション (#21) / docs/common/18_ARCHITECTURE.md 新規 (#9, #34, #39) / STABLE N=2 達成 (PR #169)
34. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.19 3 タブ監視品質向上 — tail -f → -F (ローテーション耐性) / tmux attach → new-session -A (attach-or-create) / JSON 破損時リトライ + 前回値保持 (外部評価 2026-04-17 追加指摘 #1, #3, #5) (PR #170)
35. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.20 CI testResults.xml 移行 (reports/) + .codex/config.toml.example テンプレ化 + ONBOARDING.md 刷新 + 外部レビュー即時対応 3 件 (PR #170)
36. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.21 state.schema.json 拡張 (frontier / message_bus / learning / debug / onboarding / improvement) + docs/common/18_ARCHITECTURE.md Agent 数修正 (25体) + scripts/update-readme-stats.js + CI README 自動整合ゲート (PR #171)
37. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#172] v3.2.22 state.json.example スキーマ整合修正 (message_bus 構造 / debug 型) + scripts/validate-state-example.js + CI バリデーションステップ (Issue #172) (PR #173)
38. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#174] v3.2.23 cron-launcher.sh SIGTTOU 停止バグ修正 — timeout --foreground (3箇所) + tmux pipe-pane 削除 / 本番サーバー検証済み (Issue #174) (PR #175)
39. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#176] v3.2.24 Memory MCP 退避機能 — memory-mcp-evacuation.md + pre-compact.js evacuation JSON + hooks.json PreCompact + 08_AgentTeams対応表クリーンアップ (Issue #176)
40. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#178] v3.2.25 Loop レポート reports/ 統合 — build-loop / improve-loop Output 節を reports/.loop-*.md に統一 / テンプレ同期 / reports/README.md ✅ 更新 (Issue #178)
41. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#180] v3.2.26 tests/ サブディレクトリ分類 — unit / integration / smoke 17 ファイル分類 / $PSScriptRoot パス修正 / tests/README.md 追加 / 477 PASS (Issue #180)

## Auto Extracted From Agent Teams Matrix

(自動抽出対象の未実装機能なし — 全項目実装完了)
## GitHub Issues Sync

(No open issues)


































