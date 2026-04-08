# CHANGELOG

## [v2.9.0-dev] - 2026-04-08

### Phase 3: Self Evolution & Architecture Check (Issue #49, #50)

#### 🧠 Self Evolution システム実装 (Issue #50)
- `scripts/lib/SelfEvolution.psm1` 新規作成
- `Invoke-SelfEvolutionCycle` — フェーズ別振り返り・改善提案・次アクション自動生成
- `Save-EvolutionRecord / Get-EvolutionHistory` — セッション記録のJSON永続化
- `Get-FrequentLessons` — 繰り返し学習事項のランキング集計
- `Show-EvolutionSummary` — 過去N セッションの成功率・学習サマリー表示
- `tests/SelfEvolution.Tests.ps1` Pester テスト 20件追加

#### 🏗️ Architecture Check Loop実装 (Issue #49)
- `scripts/lib/ArchitectureCheck.psm1` 新規作成
- `Invoke-ArchitectureCheck` — ファイルスキャン + 禁止パターン検出 (5ルール)
- `Get-ArchitectureViolations` — Severity別フィルタ取得
- `Show-ArchitectureCheckReport` — 違反レポート可視化
- `Test-ModuleDependencies` — モジュール間依存関係の定義検証
- 検出ルール: DIRECT_PUSH_MAIN / HARDCODED_SECRET / MISSING_STRICT_MODE / CIRCULAR_IMPORT / MISSING_ERROR_HANDLING
- `scripts/test/Test-ArchitectureCheck.ps1` スタンドアロン実行スクリプト追加
- `tests/ArchitectureCheck.Tests.ps1` Pester テスト 15件追加
- Start-Menu にメニュー項目「11. Architecture Check」追加

#### 🔀 PR #48 マージ (SSH linuxBase修正)
- `LauncherCommon.psm1`: ドライブレター自動検出・重複回避機能追加
- `tests/LauncherCommon.Tests.ps1` 77件の新規テスト追加
- 各種ドキュメント・設定テンプレート更新

### テスト・CI
- テスト数: 269 (v2.8.0) → 304 (+35件)
- CI: 全テスト PASS

### 変更ファイル (主要)
- `scripts/lib/SelfEvolution.psm1` (新規)
- `scripts/lib/ArchitectureCheck.psm1` (新規)
- `scripts/test/Test-ArchitectureCheck.ps1` (新規)
- `tests/SelfEvolution.Tests.ps1` (新規)
- `tests/ArchitectureCheck.Tests.ps1` (新規)
- `scripts/main/Start-Menu.ps1` (メニュー項目11追加)
- `README.md` (Phase 3対応全面更新)

---

## [v2.8.0] - 2026-04-06

### Issue同期 CI/hooks 統合 (PR #45)
- `scripts/tools/Sync-Issues.ps1` 新規作成 (status/check/sync/sync-to-github)
- `.github/workflows/issue-sync.yml` 新規作成 (Issue イベントトリガー自動同期)
- `ci.yml` に TASKS.md フォーマット検証ステップ追加
- `tests/Sync-Issues.Tests.ps1` Pester テスト 9 件追加

### START_PROMPT v6.3 更新 (PR #44)
- ClaudeOS v6.3 Codex 統合版テンプレート反映
- Codex Plugin 統合・review gate 運用ルール・Agent Teams 役割分担明確化

### unapproved verbs 修正 (PR #43)
- `Start-ClaudeCode.ps1` の `-DisableNameChecking` 追加

### テスト・CI
- テスト数: 228 (v2.7.1) → 237 (+9 件)
- CI: 全 PR パス
- Phase 2 完了率: 10/10 (100%)

### 変更ファイル (主要)
- `scripts/tools/Sync-Issues.ps1` (新規)
- `.github/workflows/issue-sync.yml` (新規)
- `.github/workflows/ci.yml` (検証ステップ追加)
- `tests/Sync-Issues.Tests.ps1` (新規)
- `Claude/templates/claude/START_PROMPT.md` (v6.3 更新)

---

## [v2.7.1] - 2026-04-06

### ClaudeOS v6 カーネル文書全面更新 (PR #36)
- Token フェーズ別配分を全文書に反映 (Monitor 10% / Development 40% / Verify 30% / Improvement 20%)
- 残時間管理 (state.json ベース) を各ループ・エグゼクティブ文書に統合
- Agent Teams 運用方針追加 (可視化・責務分離・Token 不足時の CTO 判断)
- CLAUDE.md をグローバル設定 (ベストプラクティス版) に改訂
- state.json を .gitignore に追加

### Worktree Manager 実装 (PR #37, Issue #32)
- `scripts/lib/WorktreeManager.psm1` 新規作成
- New/Get/Switch/Remove-Worktree, Get-WorktreeSummary
- Windows パス正規化対応 (IsMain 判定)
- `scripts/test/Test-WorktreeManager.ps1` Start-Menu 統合
- `tests/WorktreeManager.Tests.ps1` Pester テスト 15 件

### Issue/Backlog 自動生成 (PR #38, Issue #33)
- `scripts/lib/IssueSyncManager.psm1` 新規作成
- Sync-IssuesToTasks / Sync-TasksToIssues 双方向同期
- Get-SyncStatus 差分検出
- DryRun サポート
- `tests/IssueSyncManager.Tests.ps1` Pester テスト 16 件

### MCP Health Check・Agent Teams 機能強化 (PR #40)
- `Start-ClaudeCode.ps1` に Pre-Launch Diagnostics 追加 (MCP + Agent Teams 自動チェック)
- `McpHealthCheck.psm1` に Invoke-McpRuntimeProbe, Get-McpQuickStatus 追加
- `AgentTeams.psm1` に Get-AgentCapabilityMatrix, Show-AgentCapabilityMatrix, Get-AgentQuickStatus 追加

### Worktree 自動クリーンアップ (PR #41)
- `Invoke-WorktreeCleanup`: マージ済みブランチの Worktree 自動削除
- Git 2.38+ の `+` マーカー対応
- Pester テスト 3 件追加

### テスト・CI
- テスト数: 129 (v2.5.1) → 228 (+99 件)
- CI: 全 PR パス

### 変更ファイル (主要)
- `scripts/lib/WorktreeManager.psm1` (新規)
- `scripts/lib/IssueSyncManager.psm1` (新規)
- `scripts/lib/McpHealthCheck.psm1` (機能追加)
- `scripts/lib/AgentTeams.psm1` (機能追加)
- `scripts/main/Start-ClaudeCode.ps1` (Pre-Launch Diagnostics)
- `scripts/main/Start-Menu.ps1` (メニュー項目追加)
- `tests/WorktreeManager.Tests.ps1` (新規)
- `tests/IssueSyncManager.Tests.ps1` (新規)
- `.claude/claudeos/` 配下カーネル文書 18 ファイル
- `CLAUDE.md`, `README.md` (全面更新)

---

## [v2.7.0] - 2026-04-06

### MCP ヘルスチェックモジュール化 (PR #29)
- `scripts/lib/McpHealthCheck.psm1` 新規作成 (339行)
- `Test-AllTools.ps1` からMCPロジック約200行を分離・モジュール委譲
- `scripts/test/Test-McpHealth.ps1` スタンドアロン実行スクリプト追加
- `tests/McpHealthCheck.Tests.ps1` Pesterテスト追加
- Start-Menu にメニュー項目「8. MCP ヘルスチェック」追加

### Agent Teams ランタイムエンジン (PR #30)
- `scripts/lib/AgentTeams.psm1` 新規作成 (380行)
- 37 Agent 定義（.md frontmatter）のランタイム読み込み
- 17パターンのタスク種別自動分類
- backlog-rules.json 連携による優先度・オーナー自動判定
- 7 Core Roles + タスク固有 Specialists の2層 Team 構成
- `scripts/test/Test-AgentTeams.ps1` スタンドアロン実行スクリプト追加
- `tests/AgentTeams.Tests.ps1` Pesterテスト追加
- Start-Menu にメニュー項目「9. Agent Teams ランタイム」追加

### ドキュメント更新 (PR #31)
- Agent Teams 対応表: 対応レベル更新 (Agent Teams: 1→3, MCP: 2→4)
- TASKS.md: P1完了3件反映、自動抽出セクションメタデータ付与
- README.md: v2.7.0 全面更新

### 変更ファイル
- `scripts/lib/McpHealthCheck.psm1` (新規)
- `scripts/lib/AgentTeams.psm1` (新規)
- `scripts/test/Test-McpHealth.ps1` (新規)
- `scripts/test/Test-AgentTeams.ps1` (新規)
- `tests/McpHealthCheck.Tests.ps1` (新規)
- `tests/AgentTeams.Tests.ps1` (新規)
- `scripts/test/Test-AllTools.ps1` (モジュール委譲)
- `scripts/main/Start-Menu.ps1` (メニュー項目追加)
- `docs/common/08_AgentTeams対応表.md` (対応レベル更新)
- `TASKS.md` (P1完了反映)
- `README.md` (全面更新)
- `CHANGELOG.md` (本エントリ)

---

## [v2.6.0] - 2026-04-05

### ClaudeOS v6
- Token管理・残時間管理・統合判断
- ループ時間を30m/2h/1h/1hに再配分

---

## [v2.5.1] - 2026-04-05

### 5時間最適化
- 全システム5時間最適化
- ループ時間・設定・ドキュメント・README一括更新

---

## [v2.5.0] - 2026-04-04

### マルチCLI設定
- マルチCLI設定・ClaudeOSプラグインテンプレート・PTY bridge堅牢化

---

## [v2.1.0] - 2026-03-13

### 修正内容

#### SSH 起動の安定化
- `Start-Process -NoNewWindow -Wait -PassThru` による直接コマンド方式に変更
- 従来の bash スクリプト転送方式を廃止し SSH コマンドを直接実行
- SSH 接続オプション (`ConnectTimeout=10`, `StrictHostKeyChecking=accept-new`) を追加
- SSH 終了時のエラー表示を修正: exit code 255（接続失敗）のみをエラーとして扱う

#### ツール起動コマンドの統一
- GitHub Copilot CLI の起動コマンドを `copilot --yolo` に統一（ローカル・SSH 共通）
- ローカル Copilot 起動を `Start-Process` に変更し PowerShell 引数展開問題を解消

#### メニュー改善
- 「最近使用したプロジェクト」セクション（R1〜RC）を Start-Menu から削除

#### エラー修正
- `Set-StrictMode -Version Latest` 環境での `$LASTEXITCODE` 未設定エラーを解消
- `$LASTEXITCODE = 0` 事前初期化により StrictMode 互換性を確保

### 変更ファイル
- `scripts/main/Start-ClaudeCode.ps1`
- `scripts/main/Start-CodexCLI.ps1`
- `scripts/main/Start-CopilotCLI.ps1`
- `scripts/main/Start-All.ps1`
- `scripts/main/Start-Menu.ps1`
- `scripts/lib/LauncherCommon.psm1`
- `config/config.json.template`
- `tests/StartScripts.Tests.ps1`

---

## [v2.0.0] - 2026 以前

初期リリース: Claude Code / Codex CLI / GitHub Copilot CLI 統合ランチャー
