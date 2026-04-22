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
42. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.27 PSScriptAnalyzer 警告ゼロ達成 — Watch-*.ps1 BOM 追加 / Diagnostics.Tests.ps1 PSReviewUnusedParameter 12件解消 / 477 PASS
43. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#182] v3.2.28 CronManager / LogManager ユニットテスト追加 — CronManager.Tests.ps1 27件 / LogManager.Tests.ps1 11件 / 515 PASS
44. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#183] v3.2.29 Phase 2 ユニットテスト追加 — MenuCommon.Tests.ps1 19件 / SSHHelper.Tests.ps1 7件 / SessionTabManager.Tests.ps1 15件 / 556 PASS
45. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#184] v3.2.30 Phase 3 ユニットテスト追加 — StatuslineManager.Tests.ps1 7件 / McpHealthCheck.Tests.ps1 6件 (InModuleScope) / 569 PASS
46. [DONE] [Priority:P1][Owner:Developer][Source:GitHub#185+#186] v3.2.31 Watch-ClaudeLog 起動時セッション検出修正 + cron-launcher.sh tmux -e 明示 env var 渡し / PROMPT_ARG サイドカーファイル化 / サーバー反映済み
47. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#188] v3.2.32 tmux ゴーストセッション修正 — Open-TmuxAttachTab: new-session -A → attach-session -t (Issue #188) (PR #189)
48. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.33 Phase 4 ユニットテスト追加 — AgentTeams.Tests.ps1 19件 / IssueSyncManager.Tests.ps1 24件 / SelfEvolution.Tests.ps1 17件 / WorktreeManager.Tests.ps1 3件 / ArchitectureCheck.Tests.ps1 18件 / 計 81件 / 650 PASS (PR #190)
49. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.34 Phase 4 テストファイル UTF-8 BOM 追加 — AgentTeams.Tests.ps1 / ArchitectureCheck.Tests.ps1 / IssueSyncManager.Tests.ps1 BOM 追加 / PSScriptAnalyzer 警告ゼロ回復 / 650 PASS (PR #193)
50. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.35 AgentTeams.psm1 モノリス分割 — 506L → AgentDefinition.ps1 / AgentTeamBuilder.ps1 / AgentCapabilityMatrix.ps1 + psm1 薄型 dot-source オーケストレーター化 / 650 PASS (commit 733b11d)
51. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.36 Watch-SessionInfoSSH TZ オフセット不整合修正 — end_time_planned の TZ ズレで残り時間が 1 時間超過する問題を start_time + max_duration_minutes 計算に切替 / ToLocalTime() 表示統一 / ドリフト警告追加 / 650 PASS (commit d09fad7)
52. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.37 scripts/lib 全ファイル UTF-8 BOM 追加 — AgentTeams 分割 3 ファイルを含む 11 ファイルに BOM 欠落 / PSScriptAnalyzer 警告 0 件回復 / 650 PASS / STABLE N=2 達成 (commit b5cc9c8)
53. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.38 SessionLogger / TemplateSyncManager ユニットテスト追加 (SessionLogger 14件 / TemplateSyncManager 16件 / 計 30件 / 680 PASS) + Watch-SessionInfo.ps1 TZ フィックス (end_time_planned → start_time + max_duration_minutes 方式) / STABLE N=2 達成 (commit ebe2045)
54. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v3.2.39 Session Info タブ 3 点修正 — Format-Duration の [int]$Span.TotalHours 銀行丸めで残り時間が +1h ズレる表示バグを [int][Math]::Floor に変更 / Watch-SessionInfo.ps1 / Watch-SessionInfoSSH.ps1 / Watch-ClaudeLog.ps1 に QuickEdit 無効化 P/Invoke 追加（クリック凍結防止）/ Session Info タブに `Enterキーで更新可能` + 動的生成再起動コマンド常時表示 / README v3.2.37 → v3.2.39、テスト件数 650 → 680 に揃える / 680 PASS / PSScriptAnalyzer 0 件
55. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.40 cron-launcher PATH 注入 + SAFE_PROJECT 末尾アンダースコア解消 — cron-launcher.sh に PATH を注入してコマンド未検出修正 / CI SUCCESS (commit b5ef8b1, PR #196)
56. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.41 Watch-ClaudeLog.ps1 マルチ発火対応 — tail -F を Start-Job 化してマルチ発火・多重起動問題解消 / CI SUCCESS (commit 38cfe89, PR #197)
57. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.42 pwsh 7 強制 + Start-Job UTF-8 化 — タブ表示/文字化け修正 / CI SUCCESS (commit a25d52d, PR #198)
58. [DONE] [Priority:P3][Owner:Developer][Source:Manual] v3.2.43 scripts/templates/CLAUDE-Back20260331.md 削除 — v2.4.0 時点の死蔵バックアップを削除 / CI SUCCESS (commit 08c1907, PR #199)
59. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.44 Claude/templates/claudeos/ 全体を .claude/claudeos/ に deploy — ~345 ファイルを scp -r で一括転送 / CI SUCCESS (commit 6938bb2, PR #200)
60. [DONE] [Priority:P3][Owner:Developer][Source:Manual] v3.2.45 scripts/templates/claudeos/ 削除・Claude/templates/claudeos/ に一本化 — 重複ディレクトリ整理 / CI SUCCESS (commit 7d9f6a2, PR #201)
61. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.46 Watch-ClaudeLog spawn タブアイコンを PowerShell 化 — wt -p PowerShell でアイコン統一 / CI SUCCESS (commit 10289ec, PR #202)
62. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.47 wt profile を動的検出 — "PowerShell version 7" / "PowerShell 7" 両対応 / CI SUCCESS (commit 9be5999, PR #203)
63. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.48 wt profile は GUID を優先 — 空白入り名称による ArgList split 回避 / CI SUCCESS (commit 400ac1c, PR #204)
64. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.49 Agent Teams runtime 有効化 (E-1) — .claude/agents/ にも配置して Claude Code 自動 discovery 有効化 / CI SUCCESS (commit a1c4b5d, PR #205)
65. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.50 slash commands runtime 有効化 (E-2) — 39 commands を .claude/commands/ にも配置 / CI SUCCESS (commit 714e47e, PR #206)
66. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.51 skills runtime 有効化 (E-3) — 64 skills を .claude/skills/ にも配置 / CI SUCCESS (commit ebb60dd, PR #207)
67. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.52 hooks を .claude/hooks/ に配置 (E-4) — hook 定義と scripts のランタイム配置 / CI SUCCESS (commit b0db74c, PR #208)
68. [DONE] [Priority:P3][Owner:Developer][Source:Manual] v3.2.53 settings.json を Claude/templates/claude/ に一本化 — 重複設定を整理 / CI SUCCESS (commit 4b8214b, PR #209)
69. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.54 Agent ログフォーマットにアイコン + 日本語併記追加 — 👔💻🧪等のアイコンと英語名/日本語名併記を統一 / CI SUCCESS (commit 5b15d76, PR #210)
70. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.55 start.bat を pure ASCII 化 — cmd.exe parse エラー修正 / CI SUCCESS (commit b0d05a1, PR #211)
71. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.56 start.bat の if/else 括弧ネストを goto 化 — not was unexpected エラー完全解消 / CI SUCCESS (commit 5404f26, PR #212)
72. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v3.2.57 /loop → Cloud Schedule 移行 — New-CloudSchedule.ps1 新規作成 / S1専用・週6日・300分制限 / Cloudflare 403 を claude -p 中継で回避 / CI SUCCESS (commit ee6f79b, PR #213)
73. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.58 Cloud Schedule [4] 管理メニュー拡張 — OFF/ON/DEL/OFFA/ONA/DELA の6操作追加 / CI SUCCESS (commit 9b0e56a, PR #217)
74. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.59 プロジェクト選択を Cloud Schedule から動的読み込みに変更 — RemoteTrigger + Cron バッジ表示 / [0]戻る追加 / CI SUCCESS (commit c5987fb, PR #218)
75. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.60 プロジェクト選択に戻る・Cron登録状況バッジを追加 — Select-Project: [0]戻る / ☁⏱バッジ表示 / 空URL戻り値対応 / CI SUCCESS (commit ce19dbd, PR #219)
76. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.61 Cron登録後Cloud Schedule自動同期 / [6]一括同期 / owner抽出修正 — Invoke-CloudRegister後Invoke-CronAllSync呼出 / Show-CloudScheduleMenu [6]追加 / SSH URL正規表現修正 / CI SUCCESS (commit 5a0124d, PR #221)
77. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v3.2.62 Cron全同期をプロジェクト選択画面に移動・空URL/関数順序バグ修正 — Select-Project に [S] + while ループ / Invoke-CronAllSync を Select-Project より前に移動 / 空URL exit 0 ガード / Show-CloudScheduleMenu から [6] 削除 / CI SUCCESS (commit e5ee3a0, PR #222)
78. [DONE] [Priority:P2][Owner:Developer][Source:Manual] v3.2.63 PSScriptAnalyzer 0警告達成・一覧表示プロジェクト別フィルタ改善 — 空catchブロック $null=$_ / UTF-8 BOM / New-LoopPreset 改名 / SuppressMessage 関数内移動 / Watch-ClaudeLog $using: / Invoke-CloudList プロジェクトフィルタ
79. [DONE] [Priority:P1][Owner:Developer][Source:Manual] v3.2.64 管理操作（OFFA/ONA/DELA）をプロジェクトスコープに限定 — 全一括操作が全プロジェクトに影響する問題修正 / 確認ダイアログにプロジェクト名明示 / $script:RepoUrl フィルタ追加
80. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#226] v3.2.65 New-CloudSchedule.ps1 ユニットテスト追加 — Build-CreatePrompt / New-LoopPreset の 23 テストケース / dot-source exit→return パッチ戦略 / PSScriptAnalyzer 0警告
81. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#228] v3.2.66 WorktreeManager.psm1 テストカバレッジ拡充 — Get-WorktreeSummary 9件（Mock -ModuleName WorktreeManager）/ Get-WorktreeBasePath edge cases +2件 = 計 14 テストケース / PSScriptAnalyzer 0警告 / STABLE N=3達成
82. [DONE] [Priority:P2][Owner:Developer][Source:GitHub#230] v3.2.67 RecentProjects.ps1 ユニットテスト追加 — Get-RecentProject 9件（legacy/object 正規化・エラー抑制・env var展開）/ Update-RecentProject 4件（先頭挿入・重複削除・MaxHistory）/ Test-RecentProjectsEnabled 3件 = 計 17 テストケース / PSScriptAnalyzer 0警告
83. [Priority:P2][Owner:Developer][Source:GitHub#232] v3.2.68 ConfigSchema.ps1 ユニットテスト追加 + 完全自立開発対応確認 — Test-IntegerValueInRange 8件 / Test-StartupConfigSchema 22件 / Assert-StartupConfigSchema 4件 = 計 37 テストケース / テンプレート settings.json にフック定義追加 / CLAUDE.md スケジュール条件付き登録対応 / Start-ClaudeCode.ps1 START_PROMPT.md 自動再ビルド統合

## Auto Extracted From Agent Teams Matrix

(自動抽出対象の未実装機能なし — 全項目実装完了)
## GitHub Issues Sync

(No open issues)

























































