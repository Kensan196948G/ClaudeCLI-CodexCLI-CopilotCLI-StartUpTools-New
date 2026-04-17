<!-- markdownlint-disable MD024 -->

# CHANGELOG

## [v3.2.1] - 2026-04-17 — START_PROMPT CTO 全権委任 文言正規化

### 📝 ドキュメント

- **`Claude/templates/claude/instructions/_header.md`** — Monitor チェックリスト直下の宣言を `以降は全てCTO全権委任で自律開発を開始してください。` に統一（`01-session-startup.md:41` と完全一致）。
- **`Claude/templates/claude/instructions/01-session-startup.md`** — `LOOP 登録 → Codex → CTO 委任` の手順を 2 行に分割し、強調を均質化。
- **`Claude/templates/claude/START_PROMPT.md`** — 「フェーズ間でユーザーの確認・承認を求めて停止してはならない」の太字装飾をフラット化し、他の禁止項目と重み付けを揃えた。

### 🎯 意図

セッション起動時の確認・前置き・ステップ実況を template 側で恒久抑止。グローバル CLAUDE.md の「CTO 完全全権委任」原則と本プロジェクト §0 自動実行を template のレベルで一致させる。

## [v3.2.0] - 2026-04-17 — Cron HTML Mail Report

### 🎯 コードネーム: Visual Recap Mail

Cron で起動された ClaudeCode セッションの完了時に、**HTML 形式のレポートメール** を Gmail SMTP 経由で送信する機能を追加。アイコン + 色付き表組み + 実行サマリ + 次フェーズ提案まで含む。

### 🚀 新機能

- **`Claude/templates/linux/report-and-mail.py`** — Python 3 標準ライブラリのみの HTML メール送信スクリプト。
  - ステータス判定: 🟢 completed / 🔴 failed / 🟡 timeout / 🔵 running
  - 実行サマリ: Monitor / Development / Verify / Improvement の出現回数集計、エラー検出数、STABLE 達成判定
  - 次フェーズ提案: ステータス + ログ集計から自動生成 (Repair / Release / Debug / Monitor 再開)
  - インライン CSS で Gmail 表示崩れを回避
  - SMTP 送信失敗時も `cron-launcher.sh` 全体を失敗にしない fail-soft 設計
  - `--dry-run` で送信せず HTML プレビューを stdout 出力 (UTF-8 buffer 経由で Windows cp932 でも動作)
- **`Claude/templates/linux/cron-launcher.sh` 改修** — `finalize` トラップ末尾で `report-and-mail.py` を best-effort 呼び出し。timeout 終了 (exit 124) を `timeout` ステータスとして区別。
- **`config/config.json.template` 拡張** — `email` セクション追加。SMTP 認証情報は **環境変数経由** (`CLAUDEOS_SMTP_USER` / `CLAUDEOS_SMTP_PASS`)、config.json には絶対に書かない設計。
- **`docs/common/16_HTMLメールレポート設定.md`** — Gmail アプリパスワード取得 → `~/.bashrc` または crontab 内 export での配置 → スクリプト配置 → `--dry-run` 検証 → 実機テスト送信までの完全手順ドキュメント。

### 🛡️ セキュリティ設計

- アプリパスワードは **config.json に書かない**(git commit リスク回避)
- Linux 環境変数 `CLAUDEOS_SMTP_USER` / `CLAUDEOS_SMTP_PASS` で管理
- `~/.env-claudeos` は `chmod 600` 必須
- cron は `~/.bashrc` を読まないため、crontab 内 export または env ファイル source 方式を docs で明示

### 📂 メール内容

| セクション | 内容 |
|---|---|
| ヘッダ | プロジェクト名 + ステータスアイコン + 件名 |
| メタ情報表 | ステータス / プロジェクト / セッション ID / ホスト / 開始 / 終了 / 総時間 / ログパス |
| 実行サマリ表 | 4 フェーズの出現回数 + エラー数 + ログ行数 + STABLE 達成 |
| ログ末尾 | 最後の 15 行 (ダーク背景・等幅) |
| 次フェーズ提案 | ステータス連動の自動提案文 |

### ✅ 検証

- Python 3.14 syntax check pass
- bash -n syntax check pass
- JSON template valid
- dry-run HTML 生成: 6505 bytes、9 項目内容検証 PASS (STABLE/時間/アイコン/フェーズ/プロジェクト名)

---

## [v3.1.0] - 2026-04-16 — Cron / Session Info Tab / Statusline 全適用

### 🎯 コードネーム: Claude-Only Launcher

ランチャーを **Claude Code 専用** に整理し、Linux crontab 連携・Session Info タブ・Statusline グローバル適用・Slash commands を新設。

### 🚀 新機能

- **メニュー 12: Cron 登録・編集・削除** — Linux crontab に `# CLAUDEOS:<uuid>` アンカ付きで週次自動起動を登録。auto mode で `timeout 5h claude` を実行。他の cron エントリを破壊せず安全に Add / Remove / List 可能。
- **メニュー 13: Statusline 設定** — Windows 側 `~/.claude/settings.json` の `statusLine` を Linux 側へ一括適用 (Python merge + バックアップ)。
- **Windows Terminal 2 タブ構成** — S1 / L1 / Cron 起動時にメインタブに加えて「Claude Session Info」タブを自動生成。`session.json` を 1 秒間隔で poll し、開始時刻 / 終了予定 / 残り時間を秒単位カウントダウン表示。
- **Slash commands 6 本** (`.claude/commands/` に自動 deploy):
  - `/cron-register` `/cron-cancel` `/cron-list`
  - `/work-time-set` `/work-time-reset` `/session-info`
- **Linux 側 cron-launcher.sh** — `/home/kensan/.claudeos/cron-launcher.sh` に配置され、`timeout` + `session.json` 更新 (jq / sed fallback) で安全に auto mode 実行。

### 🗑️ 削除

- メニュー `S2` (Codex CLI SSH 起動) / `S3` (GitHub Copilot CLI SSH 起動) / `L2` / `L3` を削除。
- リポジトリは **Claude Code 専用ランチャー** として位置づけを明確化。
- `Start-CodexCLI.ps1` / `Start-CopilotCLI.ps1` ファイル自体は残置 (`config.json` の `tools.codex.enabled = false` / `tools.copilot.enabled = false` で無効化)。

### 🆕 追加ファイル (15 件)

| カテゴリ | ファイル |
|---|---|
| Lib | `scripts/lib/CronManager.psm1`, `scripts/lib/SessionTabManager.psm1`, `scripts/lib/StatuslineManager.psm1` |
| Main | `scripts/main/New-CronSchedule.ps1`, `scripts/main/Set-Statusline.ps1`, `scripts/main/Show-SessionInfoTab.ps1` |
| Tools | `scripts/tools/Watch-SessionInfo.ps1` |
| Test | `scripts/test/Test-CronAndSession.ps1` |
| Templates | `Claude/templates/linux/cron-launcher.sh`, `Claude/templates/claudeos/commands/{cron-register,cron-cancel,cron-list,work-time-set,work-time-reset,session-info}.md` |

### 🔧 修正ファイル (4 件)

- `scripts/main/Start-Menu.ps1` — S2/S3/L2/L3 削除、メニュー 12/13 追加
- `scripts/main/Start-ClaudeCode.ps1` — session.json 生成 + 情報タブ自動起動 + commands/ と cron-launcher.sh の SSH 配布
- `config/config.json.template` — `cron` / `sessionTabs` / `statusline` セクション新設、`codex.enabled=false` / `copilot.enabled=false`
- `README.md` — v3.1.0 新機能のドキュメント化、アーキテクチャ図更新

### ✅ 検証

- `Test-CronAndSession.ps1`: **19 / 19 PASS** (CronManager 純粋関数 + SessionTabManager ローカル CRUD)
- 9 本の PowerShell ファイル構文チェック (Parser.ParseFile) 全緑
- CI 全 4 件 SUCCESS (test-and-validate / Secrets scan (gitleaks) / PSScriptAnalyzer / CodeRabbit)

### 関連

- PR: [#140](https://github.com/Kensan196948G/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/pull/140)
- Squash commit: `153d0d8`

---

## [v3.0.0] - Unreleased (Phase 4: v3.0.0 GA Release 準備中)

### 🎯 コードネーム: Autonomous Runtime

### Phase 4 進行中の変更

#### 🧭 ClaudeOS v8 — Weekly Optimized Loops (2026-04-14)

- ループ構成を週次 MAX 20x 運用に最適化 (合計 5 時間維持)
  - Monitor: `30m` → `30min` (表記統一)
  - Development: `60m` → `2h`
  - Verify: `45m` → `1h15m`
  - Improvement: `45m` → `1h15m`
- Token 配分を再調整 (Verify 20% → 25% / Improvement 10% → 15%)
  - 品質ゲートと負債返済に +10% を確保
- 行動原則に `One tab, one project / Rest on Sunday` を追加
- 対象ファイル: `CLAUDE.md`, `~/.claude/CLAUDE.md`, `Claude/templates/claude/**`, `.claude/claudeos/commands/team-onboarding.md`, `README.md`

### Phase 4 残タスク (GA リリース前提条件)

- [ ] **セキュリティ監査** (P1) — secrets 管理・権限設定の最終確認
- [ ] **E2E テスト整備** (P2) — 全 Pester テスト + シナリオ E2E 検証
- [ ] **v3.0.0 リリースノート最終版** (P2) — 本 CHANGELOG エントリの完成
- [ ] **`v3.0.0` GitHub Release タグ作成** (P2) — バイナリ配布

### Go/No-Go 基準

以下をすべて満たすこと:

- [x] 全 Pester テスト SUCCESS (311 件)
- [x] CI 全ステップ SUCCESS
- [x] README / docs 最新状態 (ClaudeOS v7.5)
- [x] P1 Open Issue = 0
- [ ] セキュリティ監査 合格
- [ ] 対応レベル目標の 80% 以上達成

---

## [v2.9.0] - 2026-04-14 (STABLE)

### ClaudeOS v7.5 — Boot Sequence 完全自動化 + CodeRabbit 統合

#### 🚀 Boot Sequence Step 3/7/9 完全実装 (Issue #68, #70, #71)

- **Step 3 Memory Restore** (PR #81): `McpHealthCheck.psm1` の `Get-McpHealthReport` でワイヤリング完了
- **Step 7 Agent Init** (PR #80): `AgentTeams.psm1` の `Get-AgentTeamReport` でワイヤリング完了
- **Step 9 Dashboard** (PR #82): `state.json` KPI / フェーズ統合 Dashboard 実装完了
- MVP プレースホルダー状態 (Step 1/2/4/9) → 完全実装 (Step 1/2/3/4/7/9)

#### 🐰 CodeRabbit Review 統合 (PR #83, v7.5 追加)

- `/coderabbit:review` コマンド統合
- 静的解析 (40+ 解析器) による Verify 補助
- Codex レビューの代替ではなく、網羅性と深度の両立
- STABLE 判定条件に CodeRabbit Critical/High = 0 を追加

#### 👥 /team-onboarding コマンド (PR #88, v7.5 追加)

- Agent Teams 新規メンバー向け自動オンボーディング
- プロジェクト構造・運用ルール・ループ設計を段階的に案内

#### ⏱ ループ時間最適化 (PR #88)

- Development: 2h → 60m
- Verify: 1h → 45m
- Improve: 1h → 45m
- Max 20x 週次制限下での効率最大化

#### 🛡️ Issue Sync ワークフロー修正 (Issue #85, PRs #86 #87)

- `issues` イベント自動トリガーを無効化し branch protection 競合を解消
- push から PR 自動作成方式へ変更

#### 🔧 その他改善 (PRs #77, #79, #84, #89)

- PR #77: gitleaks workflow + Agent Teams Light mode
- PR #79: フェーズ別モデル制御設定 (opusplan for Development)
- PR #84: `.gitignore` に claude-mem 自動生成 `CLAUDE.md` を追加
- PR #89: README + v3ロードマップ Phase 3 完了・Phase 4 着手反映

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
- テスト数: 269 (v2.8.0) → 311 (+42件)
- CI: 全テスト PASS (14/14 SUCCESS)
- CodeRabbit: 統合済み (Critical/High = 0)

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
