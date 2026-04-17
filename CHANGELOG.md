<!-- markdownlint-disable MD024 -->

# CHANGELOG

## [v3.2.12] - 2026-04-17 — PSUseOutputTypeCorrectly 警告 37 件解消

### 🎯 概要

PSScriptAnalyzer `PSUseOutputTypeCorrectly` ルール警告を解消。
7 ファイル 13 関数に `[OutputType()]` 属性を追加。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/lib/ArchitectureCheck.psm1` | `Test-ModuleDependency` → `[OutputType([System.Object[]])]` |
| `scripts/lib/Config.psm1` | `Test-StartupConfigSchema` / `Assert-StartupConfigSchema` / `Get-RecentProject` に `[OutputType()]` |
| `scripts/lib/LauncherCommon.psm1` | `Find-AvailableDriveLetter` / `Resolve-SshProjectsDir` に `[OutputType([System.String])]` |
| `scripts/lib/LogManager.psm1` | `Start-SessionLog` / `Get-LogSummary` に `[OutputType([System.Collections.Hashtable])]` |
| `scripts/lib/MessageBus.psm1` | `Get-BusMessage` / `Confirm-BusMessage` / `Get-BusStatus` / `Initialize-MessageBus` に `[OutputType()]` |
| `scripts/lib/SelfEvolution.psm1` | `Get-EvolutionStorePath` / `Get-EvolutionHistory` / `Get-FrequentLesson` に `[OutputType()]` |
| `scripts/lib/SSHHelper.psm1` | `ConvertTo-EscapedSSHArgument` / `Test-SSHConnection` に `[OutputType()]` |

### ✅ 検証結果

- `Invoke-ScriptAnalyzer -IncludeRule PSUseOutputTypeCorrectly` = **0 件**
- `Invoke-Pester` Passed: **477** / Failed: **0**

## [v3.2.11] - 2026-04-17 — PSAvoidUsingPositionalParameters 警告解消

### 🎯 概要

PSScriptAnalyzer `PSAvoidUsingPositionalParameters` ルール警告を解消。
`Join-Path`・`Assert-Eq`・`Assert-Match`・`Write-BootStep` の位置引数呼び出しを
名前付き引数 (`-Path -ChildPath`、`-Expected -Actual -Label` 等) へ変換。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/lib/SelfEvolution.psm1` | `Join-Path` → `-Path -ChildPath` |
| `tests/ArchitectureCheck.Tests.ps1` | `Join-Path` → `-Path -ChildPath` |
| `tests/SelfEvolution.Tests.ps1` | `Join-Path` → `-Path -ChildPath` |
| `tests/E2E.Tests.ps1` | 3/4引数 `Join-Path` → `-Path -ChildPath` (2件) |
| `scripts/test/Test-CronAndSession.ps1` | `Join-Path` 2件 + `Assert-Eq` 12件 + `Assert-Match` 2件 → 名前付き引数 |
| `scripts/main/Start-ClaudeOS.ps1` | `Write-BootStep` → `-Number -Name -Status` |

### ✅ 検証結果

- `Invoke-ScriptAnalyzer -IncludeRule PSAvoidUsingPositionalParameters` = **0 件** (対象ファイル)
- `Invoke-Pester` Passed: **477** / Failed: **0**

## [v3.2.10] - 2026-04-17 — PSReviewUnusedParameter 警告 7 件解消

### 🎯 概要

PSScriptAnalyzer `PSReviewUnusedParameter` ルール警告 7 件を解消。
偽陽性（ハッシュテーブルキー代入・スコープ継承）は `SuppressMessageAttribute` で抑制。
真の未使用は実際に使用するよう修正（LauncherCommon.psm1 の `ToolLabel`）または
`Add-Member` パターンへ変更（TokenBudget.psm1 の `current_phase`）。

### 🔧 変更対象（6 ファイル・7 件）

| ファイル | パラメータ | 対応 |
|---|---|---|
| `scripts/lib/ArchitectureCheck.psm1` | `IncludeWarnings` | SuppressMessage（将来 API 確保） |
| `scripts/main/Start-ClaudeOS.ps1` | `DryRun`, `NonInteractive` | SuppressMessage（Boot Sequence Phase 3 予定） |
| `scripts/setup/setup-windows-terminal.ps1` | `UseAcrylic` | SuppressMessage（ハッシュテーブルキー偽陽性） |
| `scripts/lib/LauncherCommon.psm1` | `ToolLabel` | 実際に使用するよう修正（WARN ログへ追加） |
| `scripts/lib/TokenBudget.psm1` | `Phase` | `Add-Member -Force` で `current_phase` を設定 |
| `scripts/tools/Sync-AgentTeamsBacklog.ps1` | `ApplyMetadata` | スコープ継承を明示的パラメータ渡しに変更 |

### ✅ 検証結果

- `Invoke-ScriptAnalyzer -IncludeRule PSReviewUnusedParameter` = **0 件**
- `Invoke-Pester` Passed: **477** / Failed: **0**
- CI STABLE N=2 達成

## [v3.2.9] - 2026-04-17 — PSUseShouldProcessForStateChangingFunctions 警告 26 件解消

### 🎯 概要

PSScriptAnalyzer `PSUseShouldProcessForStateChangingFunctions` ルール警告 26 件を解消。
自律 CLI ツールとして `-WhatIf`/`-Confirm` の実装は CTO 全権委任原則と矛盾するため、
全件を `SuppressMessageAttribute` で抑制。ロジック変更なし。

### 🔧 変更対象

| Justification | 件数 | 代表関数 |
|---|---|---|
| Internal autonomous CLI function | 15 | `New-AgentTeam`, `Set-CronManagerConfig`, `Remove-ClaudeOSCronEntry`, `New/Remove-Worktree` |
| Factory function returns in-memory object | 11 | `New-CronEntryId`, `New-LauncherExecutionContext`, `New-BusSection`, `New-TokenState` |

**対象ファイル（12 ファイル）**: AgentTeams.psm1, Config.psm1, CronManager.psm1,
LauncherCommon.psm1, LogManager.psm1, MessageBus.psm1, SessionTabManager.psm1,
setup-windows-terminal.ps1, Start-ClaudeCode.ps1, TokenBudget.psm1, Update-TASKS.ps1,
WorktreeManager.psm1

### ✅ 検証結果

- `Invoke-ScriptAnalyzer -IncludeRule PSUseShouldProcessForStateChangingFunctions` = **0 件**
- `Invoke-Pester` Passed: **477** / Failed: **0**
- CI STABLE N=2 達成

---

## [v3.2.8] - 2026-04-17 — PSUseSingularNouns 警告 36 件解消

### 🎯 概要

PSScriptAnalyzer `PSUseSingularNouns` ルール警告 36 件を解消。
関数名の複数形名詞 32 件を単数形にリネーム、誤検知 4 件を `SuppressMessageAttribute` で抑制。
全呼び出し元 70 ファイルを一括更新。コードロジック変更なし。

### 🔧 変更対象

| 対応方法 | 件数 | 対象例 |
|---|---|---|
| 関数リネーム（複数→単数） | 32 | `Get-GitHubIssue`, `Sync-IssueToTask` |
| SuppressMessageAttribute（誤検知） | 4 | `Test-McpCommandExists`, `Assert-Throws` |

#### リネーム対応一覧（主要）

| 旧名 | 新名 |
|---|---|
| `Import-AgentDefinitions` | `Import-AgentDefinition` |
| `Get-RecentProjects` | `Get-RecentProject` |
| `Get-ClaudeOSCronEntries` | `Get-ClaudeOSCronEntry` |
| `Get-GitHubIssues` | `Get-GitHubIssue` |
| `Sync-IssuesToTasks` | `Sync-IssueToTask` |
| `Sync-TasksToIssues` | `Sync-TaskToIssue` |
| `Get-LauncherMetadataEntries` | `Get-LauncherMetadataEntry` |
| `Get-BusMessages` | `Get-BusMessage` |
| `Get-AllToolsDiagnostics` | `Get-AllToolsDiagnostic` |

#### SuppressMessageAttribute 抑制（誤検知）

| 関数名 | 理由 |
|---|---|
| `Test-McpCommandExists` | `Exists` は動詞サフィックス、複数名詞ではない |
| `Test-CommandExists` | 同上 |
| `Assert-Throws` | `Throws` は動詞形 |
| `Initialize-JsonRootMembers` | `Members` は JSON プロパティ集合を指すドメイン概念 |

### 🛡️ 設計判断

- **属性配置**: `SuppressMessageAttribute` は関数内 `param()` ブロック直前に配置（PowerShell 構文規則）
- **ロジック変更ゼロ**: リネームのみ。全呼び出し元を一括置換
- **テスト全通過**: Pester 477 tests Passed: 477 / Failed: 0

### 🔗 参照

- Issue: #157
- PR: #158

---

## [v3.2.7] - 2026-04-17 — PSUseBOMForUnicodeEncodedFile 警告 35 件解消

### 🎯 概要

PSScriptAnalyzer `PSUseBOMForUnicodeEncodedFile` ルール警告 35 件を解消。
非 ASCII 文字（日本語コメント等）を含む 35 ファイルに UTF-8 BOM を追加。
コードロジック変更・関数リネームなし。

### 🔧 変更対象 (35 ファイル)

| カテゴリ | ファイル数 |
|---|---|
| `scripts/lib/*.psm1` | 12 |
| `scripts/main/*.ps1` | 6 |
| `scripts/test/*.ps1` | 2 |
| `scripts/tools/*.ps1` | 2 |
| `tests/*.Tests.ps1` | 12 |
| `Claude/templates/claude/` | 1 |

### 🛡️ 設計判断

- **ロジック変更ゼロ**: `[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($true))` による純粋なエンコーディング変更のみ
- **BOM 二重付与防止**: 先頭 3 バイト (EF BB BF) を事前チェックして SKIP
- **テスト全通過**: Pester 477 tests Passed: 477 / Failed: 0

### 🔗 参照

- Issue: #155
- PR: #156 (予定)

---

## [v3.2.6] - 2026-04-17 — PSUseApprovedVerbs 警告 9 件解消

### 🎯 概要

PSScriptAnalyzer `PSUseApprovedVerbs` 警告 9 件を 8 ファイルで解消。PowerShell 承認済み動詞 (`Get-Verb`) に準拠した関数名への改名により、IDE 補完精度とコードベース一貫性を向上。

### 🔧 変更対象 (8 ファイル)

| 旧名称 | 新名称 | ファイル |
|---|---|---|
| `Normalize-MenuRecentToolFilter` | `ConvertTo-MenuRecentToolFilter` | `scripts/lib/MenuCommon.psm1` |
| `Normalize-MenuRecentSortMode` | `ConvertTo-MenuRecentSortMode` | `scripts/lib/MenuCommon.psm1` |
| `Escape-SSHArgument` | `ConvertTo-EscapedSSHArgument` | `scripts/lib/SSHHelper.psm1` |
| `_Show-SSHDiagnostics` | `Show-SSHDiagnostics` | `scripts/lib/SSHHelper.psm1` |
| `Parse-TaskBody` | `ConvertFrom-TaskBody` | `scripts/tools/Update-TASKS.ps1` |
| `Mask-SecretTail` | `Protect-SecretTail` | `scripts/test/Test-AllTools.ps1` |
| `Ensure-JsonRootMembers` | `Initialize-JsonRootMembers` | `scripts/setup/setup-windows-terminal.ps1` |
| `Upsert-TerminalProfile` | `Set-TerminalProfile` | `scripts/setup/setup-windows-terminal.ps1` |
| `Seed-ProjectTemplate` | `Initialize-ProjectTemplate` | `scripts/lib/LauncherCommon.psm1` |

テストファイル (`tests/SSHHelper.Tests.ps1`, `tests/Diagnostics.Tests.ps1`) の参照も一括更新済み。

### 🛡️ 設計判断

- **`PSUseApprovedVerbs` は CI Warning ではなく品質改善**: `-Severity Error` ゲートは通過しているが、将来の PSScriptAnalyzer バージョンで昇格する可能性があるため先行解消
- **`replace_all` による安全な一括更新**: 関数定義・呼び出しサイト・`Export-ModuleMember`・テストの `Describe` タイトル・`It` ブロック内呼び出しを漏れなく置換

### 🔗 関連

- Issue: #153
- PR: #154
- 前回 STABLE: PR #152 (v3.2.5 PSScriptAnalyzer 警告 10 件解消)

## [v3.2.5] - 2026-04-17 — PSScriptAnalyzer 警告 10 件解消

### 🎯 概要

PSScriptAnalyzer high-priority 警告 (`PSAvoidUsingInvokeExpression` / `PSAvoidAssignmentToAutomaticVariable` / `PSUseDeclaredVarsMoreThanAssignments`) を 7 ファイルで修正。CI Round 1 の 5 テスト失敗（`$Config` スコープ共有見落とし + `Remove-Worktree` 出力ストリーム漏れ）も回収し STABLE N=2 達成。

### 🔧 変更対象 (7 ファイル)

| ファイル | 修正内容 |
|---|---|
| `scripts/lib/WorktreeManager.psm1` | `Remove-Worktree` 呼び出しを `$null =` でラップし出力ストリーム漏れを防止 |
| `scripts/lib/CronManager.psm1` | `PSAvoidAssignmentToAutomaticVariable` — `$_` 変数をリネーム |
| `scripts/main/New-CronSchedule.ps1` | `PSUseDeclaredVarsMoreThanAssignments` 抑制コメント追加 |
| `scripts/main/Start-Menu.ps1` | `PSAvoidUsingInvokeExpression` 対応 |
| `tests/StartScripts.Tests.ps1` | `$Config = ...; $null = $Config` パターンで PSScriptAnalyzer 適合 + スコープ保持 |
| `tests/Diagnostics.Tests.ps1` | 同上 |
| `tests/WorktreeManager.Tests.ps1` | 関連テスト修正 |

### 🛡️ 設計判断

- **ドットソース + スコープ共有の落とし穴**: `BeforeAll` で `. Start-Menu.ps1` するテストでは、`$Config` を `| Out-Null` に置換すると dot-sourced 関数が実行時に `$Config` を参照できなくなる。`$null = $Config` パターンで変数をスコープに残しつつ PSScriptAnalyzer 警告を解消する
- **出力ストリーム管理**: PowerShell では bare 関数呼び出しの戻り値が呼び出し元の出力ストリームに漏れる。`$null = Func()` が `| Out-Null` より副作用制御で優れる

### 🔗 関連

- Issue: #151
- PR: #152
- 前回 STABLE: PR #150 (v3.2.4 repo rename docs, commit 46e205f)

## [v3.2.4] - 2026-04-17 — repo rename docs 反映

### 🎯 概要

2026-04-17 のリポジトリ名変更 (`ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New` → `ClaudeCode-StartUpTools-New`) に伴い、docs / config / state schema の絶対 URL / 絶対パス参照を一括置換。**22 ファイル / 計 55 箇所** を完全 1対1 置換。

### 🔧 変更対象 (22 ファイル)

| 分類 | ファイル |
|---|---|
| GitHub 連携 | `.github/copilot-instructions.md` |
| ルート docs | `AGENTS.md` / `README.md` / `SECURITY.md` / `ONBOARDING.md` / `CHANGELOG.md` |
| config | `config/README.md` / `Claude/templates/claudeos/README.md` |
| claude 系 | `docs/claude/03_使い方.md` |
| codex 系 | `docs/codex/{01_概要, 02_セットアップ, 03_使い方, 04_ベストプラクティス, AGENTS}.md` |
| copilot 系 | `docs/copilot/{01_概要, 02_セットアップ, 04_ベストプラクティス, AGENTS}.md` |
| 共通 docs | `docs/common/{08_AgentTeams対応表, 11_自律開発コア, 13_グローバル設定適用設計}.md` |
| schema | `state.schema.json` ($id の raw URL、v3.2.3 からの 1 箇所未反映分を回収) |

### 🛡️ 設計判断

- GitHub の自動 redirect で旧 URL も機能するが、**canonical URL を新名に統一**することで docs の長期整合性を確保
- 過去の PR 参照 URL（`CHANGELOG.md` の PR #140 等）も新名に統一 — rename 確定後に「歴史的に旧名だった」事実を URL に残す必要はない
- `ONBOARDING.md` は `/team-onboarding` で auto-generated だが、次回実行までの表示整合性のため今回も置換対象に含む
- `state.schema.json` の $id は v3.2.3 で raw URL 化した際、repo 名が旧名のまま残っていた（drift）を v3.2.4 で回収

### 🔗 関連

- Issue: #149
- PR: #150
- 前回 STABLE: PR #148 (v3.2.3 docs drift cleanup, commit deef2b3)
- 参照: CLAUDE.md §17 README 更新基準

## [v3.2.3] - 2026-04-17 — docs drift cleanup + state artifacts + hookify 検出強化

### 🎯 概要

v3.2.2 STABLE (PR #146) 達成後の Monitor で検出された 4 項目 (M-1..M-4) を 1 PR で整理。

### 🧹 docs drift 解消 (M-1)

- **`.claude/claudeos/CLAUDE.md` を削除** — v6 旧スタイル (`/model sonnet` 指示 / `everything-claude-code/...` パス参照 / 旧 Boot Sequence) が v8.2 ルート CLAUDE.md と矛盾し、階層 CLAUDE.md 解決で毎セッション Claude に注入されていた問題を解消。v8.2 真正値はプロジェクトルート `CLAUDE.md` と `.claude/claudeos/system/*.md` 群。

### 🗂 state 設定アーティファクト整備 (M-2)

- **`state.json.example`** を v8.2 フル対応に更新。既存版では `task_budget` / `compact` / `notification` / `effort_strategy` / `cache` / `message_bus` / `execution.current_session_*` / `stable.*_pr` 等が欠落していた。
- **`state.schema.json`** を新規配置 (JSON Schema draft/2020-12、既存 `docs/common/schemas/state.schema.json` と meta-schema 一致)。必須フィールド / enum / 型制約を明示。合わせて v7.4 時代の `docs/common/schemas/state.schema.json` (重複) を削除。
- CLAUDE.md §4 で「配置してください」と明示されていた推奨事項を実装。

### 🛡️ hookify CTO ガード 検出フレーズ拡充 (M-4)

v3.2.2 の 4 フレーズに加え、本日別セッションで観測された違反表現 4 種を本番 regex に昇格:

| フレーズ | distinctive な理由 |
|---|---|
| `この方針で進めて問題ないですか？` | 逐語連結が自然会話に出ない |
| `どの方針で進めますか？` / `どの方針にしますか？` | CTO 判断投げ返しに特有 |
| `別プラン: (a)` | 小文字括弧の選択肢列挙が典型 |
| `ユーザーに確認します:` | 自律実行停止の自己文言 |

`docs/common/17_hookify-CTO-guard.md` の pattern サンプルと検出表も更新。ローカル rule (`.claude/hookify.warn-cto-delegation-violation.local.md`) は各ユーザーが同 docs の手順で個別更新する。

### 📋 AgentTeams backlog 同期 (M-3)

- **`docs/common/08_AgentTeams対応表.md`** — Worktree Manager / Backlog Manager の対応レベルを現状 (PR #37 / PR #38 で DONE) に反映。「未実装機能」セクションは 0 件化。
- **`TASKS.md`** — Auto Extracted セクションを空同期。

### 🔗 関連

- Issue: #147
- 前回 STABLE: PR #146 (v3.2.2 hookify 3 層防御完成)
- 参照: CLAUDE.md §4 / §6 / §23

## [v3.2.2] - 2026-04-17 — hookify CTO 全権委任ガード (ランタイム層)

### 🛡️ ランタイム防御層を追加

v3.2.1 の template 正規化 + memory の feedback 保存に続き、**3 層目のランタイム防御** を追加。確認・承認を求める違反フレーズを Claude の `stop` イベントで検出し、`transcript` 全文を regex スキャンして警告する。

### 🆕 新規ファイル

- **`docs/common/17_hookify-CTO-guard.md`** — 3 層防御の位置づけ、セットアップ手順、検出フレーズ一覧、warn/block モードの選択基準、安全装置（検出しないもの）の一覧を記載。
- **`.claude/hookify.warn-cto-delegation-violation.local.md`** — ローカル専用 hookify ルール本体（`.gitignore` 対象、各ユーザーが個別配置）。

### 🔧 変更

- **`.gitignore`** — `.claude/hookify.*.local.md` と `.claude/*.local.md` を追加（hookify プラグインの `.local.md` 規約に準拠）。

### 🎯 検出フレーズ (v3.2.2 時点、false positive 低減のため distinctive なもののみ)

| フレーズ | 想定違反 |
|---|---|
| `実行してよろしいですか？` | 可逆操作に対する不要な実行確認 |
| `以下のいずれかを選んでください` / `以下のいずれかから選択してください` | 開発判断の選択肢提示 |
| `承認をお願いします。` / `ご承認をお願いします` | 計画の事前承認待ち |
| `実行前に確認してください。` | 軽微な可逆操作の確認 |

`進めますか？` / `選択肢は A / B / C` / `以下の手順で進めます：` は一般会話や docs 例示でも頻出するため **意図的に除外**（docs/common/17 の「意図的に除外したフレーズ」表を参照）。

### 📋 3 層防御マトリクス

| 層 | 対策 | 効果範囲 | バージョン |
|---|---|---|---|
| 1 | template 文字列統一 | 次回起動時 | v3.2.1 |
| 2 | memory feedback | 判断ロジック | v3.2.1 |
| 3 | hookify ランタイム | **現行セッション発話も捕捉** | v3.2.2 ← 新規 |

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

- PR: [#140](https://github.com/Kensan196948G/ClaudeCode-StartUpTools-New/pull/140)
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
