<!-- markdownlint-disable MD024 -->

# CHANGELOG

## [v3.2.107] - 2026-04-30 — WebUI 全テスト検証・デバッグ 250 項目を全プロジェクト実行の最終プロンプトに追加

### 🎯 概要
全登録プロジェクトの実行プロンプト（START_PROMPT.md）の末尾に、フロントエンド／バックエンド 250 項目テスト検証・デバッグリストを最終指示として組み込む。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `Claude/templates/claude/instructions/10-webui-final-verification.md` | **新規作成** — 250 項目 WebUI 全テスト検証・デバッグ指示ファイル |
| `Claude/templates/claude/instructions/_header.md` | 推奨読み込み順に `webui-final-verification.md` と `_footer.md` を追記 |
| `Claude/templates/claude/START_PROMPT.md` | 再ビルド（1190行 / 10ファイル + header + footer）|

### ✅ 修正後の動作

- `BUILD-StartPrompt.ps1` が `^\d` パターンで `10-webui-final-verification.md` を自動収集
- `START_PROMPT.md` の末尾（_footer.md 直前）に 250 項目検証リストが自動挿入される
- 全登録プロジェクトの cron・ローカル・SSH 実行で同一チェックリストが適用される
- フロント 110 項目（UI描画/レスポンシブ/JS/フォーム/セキュリティ/性能/UX）＋バック 140 項目（API/DB/セキュリティ/性能/バッチ/監視/障害/AI検証）の完全網羅

## [v3.2.97] - 2026-04-27 — S1 起動時 ~/パス修正 + statusline.js 自動デプロイ

### 🎯 概要
S1 起動（SSH モード）でのテンプレートデプロイに2つの問題を修正。

### 🐛 根本原因

| バグ | 原因 | 修正 |
|---|---|---|
| `~/.claudeos/cron-launcher.sh` が `~/~/.cloudeos/` に誤配置 | bash double-quoteの中では `~` は展開されない | `~` → `$HOME` に変換するロジック追加 |
| S1 起動時に `statusline.js` が Linux に自動デプロイされない | デプロイリストに含まれていなかった | `scripts/templates/statusline.js` を追加・`$HOME/.claude/statusline.js` として InitializeOnly でデプロイ |

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/main/Start-ClaudeCode.ps1` | `New-RemoteTemplateDeployScript` で `~` → `$HOME` 変換追加 / `statusline.js` デプロイ追加 |
| `scripts/templates/statusline.js` | statusline.js テンプレートとして新規追加 |

### ✅ 修正後の動作

```
S1 起動 → プロジェクト選択
→ ~/.claudeos/cron-launcher.sh が /home/kensan/.claudeos/ に正しく配置 ✅
→ ~/.claude/statusline.js が /home/kensan/.claude/ に InitializeOnly でデプロイ ✅
→ 次回 S1 からは statusline が確実に動作
```

## [v3.2.96] - 2026-04-27 — statusline.js Linux パス修正・自動デプロイ対応

### 🎯 概要
`Invoke-RemoteSettingsSync` が Windows 絶対パス (`C:/Users/kensan/.claude/statusline.js`) を
Linux に verbatim コピーしていた問題を修正。`~/.claude/` への自動変換 + `statusline.js` ファイルの
自動コピー機能を追加し、Windows / Linux 両方で statusline が動作するよう対応。

### 🐛 根本原因

| 項目 | 変更前 | 変更後 |
|---|---|---|
| `statusLine.command` | `node C:/Users/kensan/.claude/statusline.js` | `node ~/.claude/statusline.js` |
| Linux 動作 | C:/Users... パスが存在せず失敗 | `~` が OS 別に展開され両方で動作 |

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/lib/StatuslineManager.psm1` | `Copy-StatuslineScript` 関数追加 / `Invoke-RemoteSettingsSync` に Windows→Linux パス変換追加 |
| `scripts/main/Set-Statusline.ps1` | JS ファイルを Linux 側へ自動コピーするロジック追加 |
| `C:/Users/kensan/.claude/settings.json`（手動） | `statusLine.command` を `node ~/.claude/statusline.js` に変更 |

### ✅ 修正後の動作

```
メニュー12 実行
→ statusline.js を Linux ~/.claude/ へコピー
→ settings.json statusLine.command を node ~/.claude/statusline.js で書込み
→ Windows 側 settings.json も ~/. claude/statusline.js を使用
→ 次回同期で Windows 絶対パスで上書きされない ✅
```

## [v3.2.95] - 2026-04-27 — statusLine をテンプレートから削除してグローバル管理に一本化

### 🎯 概要
メニュー12（Statusline設定）がグローバル設定に書いても各プロジェクト設定に上書きされる問題を修正。
テンプレート `settings.json` から `statusLine` セクションを削除し、`~/.claude/settings.json`（グローバル）のみで管理する設計に変更。

### 🐛 根本原因
Claude Code の優先順位: プロジェクト `.claude/settings.json` > グローバル `~/.claude/settings.json`
テンプレートから配置されたプロジェクト `settings.json` に `statusLine` が書かれているため、
メニュー12 でグローバルに設定しても上書きされていた。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `Claude/templates/claude/settings.json` | `statusLine` セクション削除（グローバルに委譲） |
| Linux 全プロジェクト `.claude/settings.json` | 既存の `statusLine` を一括削除（8件） |

### ✅ 修正後の動作

```
メニュー12 → ~/ .claude/settings.json に statusLine を書き込む
           → 各プロジェクトの settings.json には statusLine なし
           → グローバル設定が全プロジェクトで即時有効 ✅
```

---

## [v3.2.94] - 2026-04-27 — statusline グローバル設定崩れを修正（InitializeOnly）

### 🎯 概要
SSH モードでの `settings.json` 上書き問題を修正。`New-RemoteTemplateDeployScript` に `-InitializeOnly` スイッチを追加し、`settings.json` は初回のみ配置・既存ファイルを上書きしない動作に変更（ローカルモードと統一）。

### 🐛 根本原因
| モード | 旧動作 | 結果 |
|---|---|---|
| SSH（`New-RemoteTemplateDeployScript`）| `cmp -s` で差分があれば**毎回上書き** | Claude 実行中に変更された settings.json がテンプレートで上書きされ statusLine 消失 |
| ローカル（`Initialize-ProjectTemplate`）| **初回のみ**配置（既存保持） | 問題なし |

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/main/Start-ClaudeCode.ps1` | `New-RemoteTemplateDeployScript` に `-InitializeOnly` スイッチを追加 |
| `scripts/main/Start-ClaudeCode.ps1` | `settings.json` のデプロイに `-InitializeOnly` を適用（line 413） |

---

## [v3.2.93] - 2026-04-27 — CTO最上位指令を _header.md と CLAUDE.md に強調追加

### 🎯 概要
CTO全権委任・5時間厳守・ループ・AgentTeams・Auto Mode・可視化・ドキュメント・GitHub Projects の10項目からなる最上位運用指令を blockquote + Bold + 絵文字で強調し、START_PROMPT.md の冒頭（61行目）と CLAUDE.md ステップ3 に配置。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `instructions/_header.md` | `## 🔥 最上位指令（必須実行）` セクション追加 |
| `CLAUDE.md` | ステップ3 を blockquote + 絵文字リスト形式に強調更新 |
| `START_PROMPT.md` | ビルド再生成（825行 → 842行） |

---

## [v3.2.92] - 2026-04-27 — instructions/ を v8.5 Ultimate Modular Prompt Pack に再編

### 🎯 概要
`Claude/templates/claude/instructions/` を v8.5 Ultimate モジュール分割構成に刷新。
旧ファイルを `BackUp/` に保存し、`github-actions-ci-manager.yml` を新規追加。
`Build-StartPrompt.ps1` によるビルドで 825行の START_PROMPT.md を生成。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `instructions/_header.md` | Modular Prompt Pack インデックスヘッダーに変更 |
| `instructions/01-09-*.md` | v8.5 Ultimate 内容に全面刷新 |
| `instructions/github-actions-ci-manager.yml` | GitHub Actions CI Manager テンプレート新規追加 |
| `instructions/BackUp/` | 旧ファイルを保存 |
| `START_PROMPT.md` | ビルド再生成（825行） |

---

## [v3.2.91] - 2026-04-27 — START_PROMPT.md を ClaudeOS v8.6 完全運用安定版に刷新

### 🎯 概要
`Claude/templates/claude/START_PROMPT.md` を **ClaudeOS v8.6（完全運用安定版・無人開発モデル）** に刷新。
v8.5 Ultimate を簡潔化・実運用最適化し、CTO全権委任宣言・Guardrail条件・KPIスコア連動ループ制御を整理。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `Claude/templates/claude/START_PROMPT.md` | ClaudeOS v8.6 完全運用安定版に刷新（226行・コンパクト化） |

### 📋 v8.6 の主な改善点

- 最上位宣言（CTO全権委任・Guardrail 3条件）を冒頭に明示
- 自律行動原則を4原則に整理（No Idle / Guarded Autonomy / Minimal Change / Always Verify）
- KPIスコア = `state.json.priority.score` に直結させてシンプル化
- フェーズ配分に Buffer 枠を追加（5〜10%）
- v8.5 の重複セクションを統廃合し226行にコンパクト化

---

## [v3.2.90] - 2026-04-27 — START_PROMPT.md を ClaudeOS v8.5 Ultimate に刷新

### 🎯 概要
`Claude/templates/claude/START_PROMPT.md` を **ClaudeOS v8.5 Ultimate（完全統合版）** に全面刷新。
Routines 最適化・state.json AI・6ヶ月リリース保証・GitHub Actions 完全連動・AI Dev Factory を統合した完全自律開発 OS テンプレートに更新。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `Claude/templates/claude/START_PROMPT.md` | ClaudeOS v8.5 Ultimate に全面刷新 |

### 📋 v8.5 Ultimate の主な追加内容

- 6ヶ月フェーズ制御表（Build/Quality/Stabilize/Release）
- KPIスコア連動ループ判定（score計算式）
- フェーズ別時間配分黄金比
- GitHub Actions 完全連動テンプレート付き
- AI Dev Factory Issue テンプレ

---

## [v3.2.89] - 2026-04-27 — メニュー大幅刷新 + ログ監視タブ発火タイミング修正

### 🎯 概要
`Start-Menu.ps1` の表示を PowerShell 7 カラー + Unicode ボーダー + 絵文字アイコン多用で全面刷新。
`Watch-ClaudeLog.ps1` の `stdbuf -oL` 依存を除去し、cron 発火タイミングの検知遅延・ミスを解消。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/main/Start-Menu.ps1` | メニュー全面刷新 — Unicode ボーダー + 絵文字アイコン + PowerShell 7 カラー |
| `scripts/tools/Watch-ClaudeLog.ps1` | `stdbuf -oL` 廃止 → `tail -F` のみ SSH 実行 + PowerShell 側 ANSI フィルタ追加 |

### 🐛 修正詳細

**ログ監視タイミング修正 (v3.2.89)**
- 根本原因: `stdbuf -oL tail ...` が Linux 環境に `stdbuf` 未インストールの場合に SSH ジョブが即終了
- 結果: `$knownLog = $latest` が設定されてしまい次回の cron 発火を"既知ログ"と判定してスキップ
- 修正: `stdbuf -oL` を除去し `tail -F` のみ実行。ANSI フィルタを PowerShell 受信側で適用

---

## [v3.2.80] - 2026-04-23 — scripts/lib 全 13 ファイルへ Set-StrictMode 追加 + PSCustomObject 安全化

### 🎯 概要
`ArchitectureCheck` で WARNING として報告されていた `Set-StrictMode -Version Latest` 未設定 13 ファイルを解消。
Config モジュール（ConfigSchema.ps1 / ConfigLoader.ps1）に存在した動的プロパティアクセス（`$Config.$field`・`$Config.tools.$toolName`）を `PSObject.Properties[$key]?.Value` パターンに書き換え、StrictMode 下でも `PropertyNotFoundException` が発生しないよう修正。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/lib/ConfigSchema.ps1` | `Set-StrictMode -Version Latest` 追加 + 動的プロパティアクセス 4 箇所を安全化 |
| `scripts/lib/ConfigLoader.ps1` | `Set-StrictMode -Version Latest` 追加 + 動的プロパティアクセス 4 箇所を安全化 |
| `scripts/lib/Config.psm1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/RecentProjects.ps1` | `Set-StrictMode -Version Latest` 追加（既存コードは PSObject.Properties パターン使用済み） |
| `scripts/lib/AgentCapabilityMatrix.ps1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/AgentDefinition.ps1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/AgentTeamBuilder.ps1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/LauncherCommon.psm1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/LogManager.psm1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/MenuCommon.psm1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/SSHHelper.psm1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/SessionLogger.ps1` | `Set-StrictMode -Version Latest` 追加 |
| `scripts/lib/TemplateSyncManager.ps1` | `Set-StrictMode -Version Latest` 追加 |

### 🔑 設計ポイント
- `$obj.$dynamicKey` → `$obj.PSObject.Properties[$dynamicKey]?.Value` で存在しないプロパティへのアクセスが `$null` を返すように変更（PropertyNotFoundException 回避）
- `?.` 演算子は PowerShell 7.1+ で利用可能（CI 環境は PS 7 対応）
- Issue #239 対応（P3）

### ✅ テスト結果
- CI: test-and-validate / PSScriptAnalyzer / Secrets scan

---

## [v3.2.79] - 2026-04-22 — tmux pipe-pane によるログ可視化 / cron-launcher.sh 自動同期

### 🎯 概要
`今すぐ実行` ([6]) 後に Watch-ClaudeLog.ps1 タブが空白になり Claude が起動していないように見える問題を修正。原因は `cron-launcher.sh` が Claude を tmux セッション内で起動するため stdout がログファイルに流れていなかったこと。`tmux pipe-pane` を追加して Claude の tmux pane 出力をログファイルに流すよう修正した。合わせて `cron-launcher.sh` の自動 Linux 同期機能を追加。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `Claude/templates/linux/cron-launcher.sh` | `tmux new-session` 直後に `tmux pipe-pane -t "$TMUX_SESSION" -o "cat >> '$LOG_FILE'"` を追加 |
| `scripts/main/New-CronSchedule.ps1` | `Invoke-SyncLauncher` / `Invoke-SyncLauncherMenu` 追加。`Invoke-CronTest` から自動呼び出し。メニュー `[8] cron-launcher.sh を同期` 追加 |

### 🔑 設計ポイント
- `tmux pipe-pane -o` の `-o` フラグで pane 出力のみをキャプチャ（入力はキャプチャしない）
- Claude の ANSI 出力がそのままログファイルに流れるため Windows Terminal の VT100 解釈でカラー表示
- cron-launcher.sh の同期は START_PROMPT.md と同じ SSH stdin pipe 方式（SCP 非依存）

### ✅ テスト結果
- 稼働中セッションへの `tmux pipe-pane` 手動適用で cron-20260422-173116.log が 233B → 95KB に増加することを確認

---

## [v3.2.78] - 2026-04-22 — Linux側 START_PROMPT.md 自動同期 / /loop スキルトリガー根本解消

### 🎯 概要
v3.2.77 で Windows テンプレートを修正したが Linux 側のデプロイ済み `.claude/START_PROMPT.md` が旧版のまま残り `/loop` スキルが引き続きトリガーされていた。`New-CronSchedule.ps1` に `Invoke-SyncStartPrompt` 関数を追加し、cron 登録・今すぐ実行・手動同期の3経路で Linux 側ファイルを最新テンプレートと同期する。また `~/.claude/claudeos/CLAUDE.md` 先頭の `/loop` コマンド行4行を削除（即時適用）。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CronSchedule.ps1` | `Invoke-SyncStartPrompt` / `Invoke-SyncMenu` 追加。`Invoke-Register`・`Invoke-EnsureStateJson`・`Invoke-CronTest` から呼び出し。メニュー `[7] START_PROMPT を同期` 追加 |
| `~/.claude/claudeos/CLAUDE.md` | 先頭4行の `/loop 30m` 等を削除（リポジトリ外・即時適用） |

### 🔑 設計ポイント
- SSH stdin pipe (`$content | ssh "cat > file"`) で SCP 依存なしにテキストファイルを転送
- `Invoke-SyncStartPrompt` は `Invoke-EnsureStateJson` が早期 return した場合でも `Invoke-Register` から直接呼ばれるためスキップなし
- `Invoke-CronTest` での起動前同期により「今すぐ実行」時も常に最新プロンプトを使用

### ✅ テスト結果
- CI: test-and-validate / PSScriptAnalyzer / Secrets scan — 全 pass

---

## [v3.2.77] - 2026-04-22 — /loop・/schedule スラッシュコマンド参照を除去

### 🎯 概要
cron 実行時の初回プロンプトに `/loop` スキルが誤起動する問題を修正。`_header.md`・`01-session-startup.md`・`CLAUDE.md`（プロジェクトルート + テンプレート）内のスラッシュコマンド構文を平文に書き換え、`Build-StartPrompt.ps1` で `START_PROMPT.md` を再生成。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `CLAUDE.md` | `/loop` `/schedule` → 平文に書き換え |
| `Claude/templates/claude/CLAUDE.md` | 同上 |
| `Claude/templates/claude/instructions/_header.md` | 同上 |
| `Claude/templates/claude/instructions/01-session-startup.md` | 同上 |
| `Claude/templates/claude/START_PROMPT.md` | Build-StartPrompt.ps1 で再生成 |

### ✅ テスト結果
- CI: test-and-validate / PSScriptAnalyzer / Secrets scan / CodeRabbit — 全 pass
- grep 確認: `/loop` `/schedule` スラッシュ構文なし（ファイルパス参照のみ）

---

## [v3.2.76] - 2026-04-22 — P1-3 ローカル cron レジストリ + P1-7 Agent Teams 使用ログ

### 🎯 概要
P1-3: CronManager.psm1 にローカルレジストリ機能を追加し、SSH なしで Windows 側から登録済みプロジェクトを参照可能に。P1-7: usage-tracker.js を新規作成し、Agent ツール呼び出しを state.json の learning.usage_history.agents に記録する PostToolUse hook を実装。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/lib/CronManager.psm1` | P1-3: Get-LocalCronRegistry / Add-LocalCronRegistryEntry / Remove-LocalCronRegistryEntry 追加。Add/Remove-ClaudeOSCronEntry から自動呼び出し |
| `.claude/claudeos/scripts/hooks/usage-tracker.js` | P1-7: 新規作成。Agent ツール呼び出しを検出し learning.usage_history.agents に記録 |
| `.claude/settings.json` | P1-7: PostToolUse[Agent] hook として usage-tracker.js を登録 |
| `Claude/templates/claude/settings.json` | P1-7: テンプレートにも同設定を反映 |
| `tests/unit/CronManager.Tests.ps1` | P1-3: Get-LocalCronRegistry テスト 6件追加 (33 → 39件) |
| `README.md` | Hooks 構成を 4個に更新（usage-tracker 追加）、バージョン・テスト件数更新 |

### ✅ テスト結果
- Pester: 776/776 passed (新規 6件含む)
- PSScriptAnalyzer: Error 0件

---

## [v3.2.75] - 2026-04-22 — P1-2/4/5 state.json 連携強化 + P2-1/2/4 docs 整備

### 🎯 概要
完全自律開発の継続性を高める state.json 連携を強化。Cron 登録時に state.json を自動生成（P1-2）、cron 起動時に前回フェーズを復元してプロンプトに注入（P1-4）、session-start.js を書き込み対応に昇格（P1-5）。ドキュメント整備として Codex optional 化（P2-2）・README タイムライン図追加（P2-4）・テスト具体化（P2-1）を実施。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CronSchedule.ps1` | P1-2: Cron 登録後に Linux 側 state.json を自動生成（未存在時のみ）+ .claude/ 未配備の警告 |
| `Claude/templates/linux/cron-launcher.sh` | P1-4: state.json から phase / consecutive_success / last_summary を復元し prompt に注入 |
| `.claude/claudeos/scripts/hooks/session-start.js` | P1-5: current_session_start_at / last_trigger を state.json に atomic 書き込み |
| `Claude/templates/claude/instructions/_header.md` | P2-2: Codex 必須表記を optional に統一 |
| `Claude/templates/claude/START_PROMPT.md` | P2-2 反映後に自動再ビルド (906行) |
| `README.md` | P2-4: Linux cron タイムライン図追加・Hooks 構成実態修正・Boot Sequence 更新 |
| `tests/integration/StartScripts.Tests.ps1` | P2-1: Step 5/6/8 テストを 3 本に具体化 |

### ✅ テスト結果
- Pester: 770/770 passed
- PSScriptAnalyzer: Error 0件

---

## [v3.2.74] - 2026-04-22 — P1-6 Codex optional化 + P2-3 完全自立チェックリスト + P1-1 Boot Sequence Step 5/6/8

### 🎯 概要
Codex を停止条件から外して optional 化（P1-6）、Linux cron 完全自律実行のための7項目チェックリストを新規作成（P2-3）、Boot Sequence の Step 5/6/8 を [SKIP] から実装済みに昇格（P1-1）。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `CLAUDE.md` / `Claude/templates/claude/CLAUDE.md` | Codex optional 化 |
| `docs/autonomy-checklist.md` | 新規作成（7項目チェックリスト） |
| `scripts/main/Start-ClaudeOS.ps1` | Step 5/6/8 実装 |

### ✅ テスト結果
- Pester: 768/768 passed

---

## [v3.2.73] - 2026-04-22 — P0 完全自律化 Cloud/Loop 残骸撤去 + CI 封鎖 + README 刷新

### 🎯 概要
/loop・/schedule・Cloud Schedule の残骸をコード・ドキュメント・CI から一掃。メニューを Linux Cron 自律実行中心に刷新。

---

## [v3.2.72] - 2026-04-22 — Architecture Check CRITICAL 1件解消

---

## [v3.2.71] - 2026-04-22 — ArchitectureCheck 偽陽性 CRITICAL 8件 → 0件修正

---

## [v3.2.70] - 2026-04-22 — /loop 残存参照を除去

---

## [v3.2.68] - 2026-04-22 — ConfigSchema.ps1 ユニットテスト追加 + 完全自立開発対応整備

### 🎯 概要
`Test-IntegerValueInRange` 8件 + `Test-StartupConfigSchema` 25件 + `Assert-StartupConfigSchema` 4件 = 37 テストケース追加。

---

## [v3.2.67] - 2026-04-22 — RecentProjects.ps1 ユニットテスト追加

### 🎯 概要
`scripts/lib/RecentProjects.ps1`（173行・3関数）のユニットテストがゼロだった問題を解消。
`Get-RecentProject`（JSON 正規化・legacy/object 両形式・エラー抑制）、`Update-RecentProject`（先頭挿入・重複削除・MaxHistory 上限）、`Test-RecentProjectsEnabled`（Config 判定）を対象に 17 テストケースを追加。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `tests/unit/RecentProjects.Tests.ps1` | 新規作成: `Get-RecentProject` 9件 + `Update-RecentProject` 4件 + `Test-RecentProjectsEnabled` 3件 = 17 テストケース |

### ✅ テスト結果
- Pester: 17/17 passed
- PSScriptAnalyzer 0 warnings

---

## [v3.2.66] - 2026-04-22 — WorktreeManager.psm1 テストカバレッジ拡充

### 🎯 概要
`scripts/lib/WorktreeManager.psm1`（375行・7関数）のテストが `Get-WorktreeBasePath` 3件のみだった問題を解消。`Get-WorktreeSummary`（`Mock -ModuleName WorktreeManager` でモック注入）と `Get-WorktreeBasePath` edge cases を追加し、14 テストケースに拡充。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `tests/unit/WorktreeManager.Tests.ps1` | `Get-WorktreeBasePath` edge cases +2件 / `Get-WorktreeSummary` 9件追加 = 計 14 テストケース |

### ✅ テスト結果
- Pester: 14/14 passed
- PSScriptAnalyzer 0 warnings (PSUseBOMForUnicodeEncodedFile 対応済み)

---

## [v3.2.65] - 2026-04-21 — New-CloudSchedule.ps1 ユニットテスト追加

### 🎯 概要
`scripts/main/New-CloudSchedule.ps1`（772行）に対するユニットテストがゼロだった問題を解消。`Build-CreatePrompt`（プロンプト文字列生成）と `New-LoopPreset`（4プリセット生成）を対象に 23 テストケースを追加。スクリプト（.ps1）を Pester から dot-source する際の `exit` 問題を `exit→return` パッチ戦略で解決。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `tests/unit/NewCloudSchedule.Tests.ps1` | 新規作成: `New-LoopPreset` 12件 + `Build-CreatePrompt` 11件 = 23 テストケース / UTF-8 BOM / PSScriptAnalyzer 0警告 |

### ✅ テスト結果
- Pester: 23/23 passed
- PSScriptAnalyzer 0 warnings (non-WriteHost)

---

## [v3.2.64] - 2026-04-21 — 管理操作（OFFA/ONA/DELA）をプロジェクトスコープに限定

### 🎯 概要
`[4] 管理` の全一括操作（OFFA/ONA/DELA）が全プロジェクトのトリガーに影響していた問題を修正。現在選択中のプロジェクトのトリガーのみを対象とするようプロンプトを変更。確認ダイアログにプロジェクト名を明示して誤操作を防止。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CloudSchedule.ps1` | Invoke-CloudManage: OFFA/ONA/DELA プロンプトに `$script:RepoShortName` / `$script:RepoUrl` フィルタ追加 / 確認ダイアログにプロジェクト名明示 / 操作ヘッダーにプロジェクト名表示 |

### ✅ テスト結果
- PSScriptAnalyzer 0 warnings (non-WriteHost)

---

## [v3.2.63] - 2026-04-21 — PSScriptAnalyzer 0警告達成・一覧表示をプロジェクト別フィルタに改善

### 🎯 概要
`New-CloudSchedule.ps1` / `New-CronSchedule.ps1` / `Watch-ClaudeLog.ps1` に残存していた PSScriptAnalyzer 警告（`PSAvoidUsingEmptyCatchBlock` 7件・`PSUseShouldProcessForStateChangingFunctions` 1件・`PSUseSingularNouns` 1件・`PSUseBOMForUnicodeEncodedFile` 1件・`PSUseUsingScopeModifierInNewRunspaces` 1件）を全解消。`[1] 一覧表示` を現在選択中のプロジェクトのトリガーのみ表示するようプロンプトを修正。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CloudSchedule.ps1` | 空catchブロック `$null = $_` 修正 / UTF-8 BOM 付与 / `New-LoopPresets` → `New-LoopPreset` 改名 / SuppressMessageAttribute を関数内に移動 / `$script:RepoUrl` 追加 / Invoke-CloudList プロジェクトフィルタ追加 |
| `scripts/main/New-CronSchedule.ps1` | 空catchブロック `$null = $_` 修正 |
| `scripts/tools/Watch-ClaudeLog.ps1` | Start-Job を `$using:` スコープ修飾子に変更 |

### ✅ テスト結果
- PSScriptAnalyzer 0 warnings (non-WriteHost)

---

## [v3.2.62] - 2026-04-21 — Cron全同期をプロジェクト選択画面に移動・空URL/関数順序バグ修正

### 🎯 概要
`[S] Cron全プロジェクトをCloud Scheduleに同期` を `Show-CloudScheduleMenu` から `Select-Project` に移動。PowerShell関数定義順序バグ（`Invoke-CronAllSync` が `Select-Project` より後に定義されていた問題）を修正。`[0] 戻る` 選択時の空URL渡しバグ修正。`Select-Project` に `while($true)` ループを追加し [S] 同期後にリスト再表示（☁バッジ更新）を実現。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CloudSchedule.ps1` | 関数定義順序修正 / Select-Project に [S] 同期 + while ループ / 空URL exit 0 ガード / Show-CloudScheduleMenu から [6] 削除 |

### ✅ テスト結果
- CI SUCCESS / Security Scan SUCCESS (commit e5ee3a0, PR #222)

---

## [v3.2.61] - 2026-04-21 — Cron登録後Cloud Schedule自動同期 / [6]一括同期 / owner抽出修正

### 🎯 概要
Cron登録直後に Cloud Schedule へ自動同期する機能を追加。`Show-CloudScheduleMenu` に `[6] Cron全プロジェクトをCloud Scheduleに同期` を追加。`Invoke-CronAllSync` 内の owner 抽出バグ（`git remote get-url origin` → SSH 形式URLで空文字になる問題）を正規表現で修正。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CloudSchedule.ps1` | Invoke-CloudRegister: 登録後 Invoke-CronAllSync 呼出し / Show-CloudScheduleMenu: [6] 追加 / Invoke-CronAllSync: owner 抽出修正 |

### ✅ テスト結果
- CI SUCCESS / Security Scan SUCCESS (commit 5a0124d, PR #221)

---

## [v3.2.60] - 2026-04-21 — プロジェクト選択に戻る・Cron登録状況バッジを追加

### 🎯 概要
`Select-Project` に `[0] 戻る` オプションと Cron 登録状況バッジ（☁/⏱）を追加。Cron バッジは RemoteTrigger 動的取得と CronManager SSH 確認を組み合わせて表示。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CloudSchedule.ps1` | Select-Project: [0]戻る追加 / ☁⏱バッジ表示 / 空URL戻り値対応 |

### ✅ テスト結果
- CI SUCCESS / Security Scan SUCCESS (commit ce19dbd, PR #219)

---

## [v3.2.59] - 2026-04-21 — Cloud Schedule プロジェクト選択を動的読み込みに変更

### 🎯 概要
`Select-Project` をハードコード2件から RemoteTrigger 動的取得 + Cron 登録状況バッジ表示に変更。`[0] 戻る` 追加。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CloudSchedule.ps1` | Select-Project: RemoteTrigger + CronManager からプロジェクト一覧取得、☁/⏱バッジ、[0]戻る |

### ✅ テスト結果
- CI SUCCESS / Security Scan SUCCESS (commit c5987fb)

---

## [v3.2.58] - 2026-04-21 — Cloud Schedule [4] を管理メニューに拡張

### 🎯 概要
`[4]` を「削除/無効化」から「管理（無効化/有効化/完全削除）」に拡張。6操作 (OFF/ON/DEL/OFFA/ONA/DELA) を追加。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `scripts/main/New-CloudSchedule.ps1` | Invoke-CloudManage: 無効化/有効化/完全削除を個別・全件で操作可能に |

### ✅ テスト結果
- CI SUCCESS / Security Scan SUCCESS / Copilot review SUCCESS (commit 9b0e56a)

---

## [v3.2.57] - 2026-04-21 — /loop → Cloud Schedule 移行 (S1専用・週6日・300分制限)

### 🎯 概要
セッション終了で消滅する `/loop` (session Cron) から Anthropic Cloud Schedule (RemoteTrigger) へ完全移行。`New-CloudSchedule.ps1` 新規作成。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `CLAUDE.md` | ステップ1: /loop → /schedule (Mon-Sat, 5h制限) |
| `scripts/main/New-CloudSchedule.ps1` | 新規: claude -p 中継で Cloud Schedule 管理 (Cloudflare 403 回避) |
| `scripts/main/Start-Menu.ps1` | メニュー14 Cloud Schedule / 15 Cron に整理 |
| `scripts/main/Start-ClaudeCode.ps1` | 起動前 QuickSetup 自動確認挿入 |
| `Claude/templates/claude/START_PROMPT.md` | /loop 廃止・Cloud Schedule 案内に更新 |
| `README.md` | Mermaid図・メニュー説明を Cloud Schedule 対応に更新 |

### ✅ テスト結果
- CI SUCCESS / Security Scan SUCCESS (commit ee6f79b)

---

## [v3.2.56] - 2026-04-20 — start.bat の if/else 括弧ネストを goto 化

### 🎯 概要
cmd.exe の括弧ネスト制限 (`not was unexpected` エラー) を goto 構造で完全解消。

### 🔧 変更対象
| ファイル | 変更内容 |
|---|---|
| `start.bat` | if/else ネストを goto ラベルに変換 |

### ✅ テスト結果
- CI SUCCESS (commit 5404f26)

---

## [v3.2.55] - 2026-04-20 — start.bat pure ASCII 化

### 🎯 概要
start.bat を pure ASCII に変換して cmd.exe parse エラーを修正。

### ✅ テスト結果
- CI SUCCESS (commit b0d05a1)

---

## [v3.2.54] - 2026-04-20 — Agent ログフォーマット アイコン + 日本語併記追加

### 🎯 概要
Agent ログフォーマットにアイコン（👔💻🧪等）と英語名/日本語名の併記表記を導入。

### ✅ テスト結果
- CI SUCCESS (commit 5b15d76)

---

## [v3.2.53] - 2026-04-20 — settings.json を Claude/templates/claude/ に一本化

### 🎯 概要
重複していた settings.json を `Claude/templates/claude/` に統一。deploy パスを整理。

### ✅ テスト結果
- CI SUCCESS (commit 4b8214b)

---

## [v3.2.52] - 2026-04-20 — hooks を .claude/hooks/ に配置 (E-4)

### 🎯 概要
hook 定義と hook scripts を `.claude/hooks/` にも配置してランタイム有効化。

### ✅ テスト結果
- CI SUCCESS (commit b0db74c)

---

## [v3.2.51] - 2026-04-20 — skills runtime 有効化 — .claude/skills/ にも配置 (E-3)

### 🎯 概要
64 skills を `.claude/skills/` にも配置してランタイム有効化。

### ✅ テスト結果
- CI SUCCESS (commit ebb60dd)

---

## [v3.2.50] - 2026-04-20 — slash commands runtime 有効化 — .claude/commands/ にも配置 (E-2)

### 🎯 概要
39 slash commands を `.claude/commands/` にも配置してランタイム有効化。

### ✅ テスト結果
- CI SUCCESS (commit 714e47e)

---

## [v3.2.49] - 2026-04-20 — Agent Teams runtime 有効化 — .claude/agents/ にも配置 (E-1)

### 🎯 概要
Agent Teams を `.claude/agents/` にも配置して Claude Code の自動 discovery を有効化。

### ✅ テスト結果
- CI SUCCESS (commit a1c4b5d)

---

## [v3.2.48] - 2026-04-20 — wt profile は GUID を優先

### 🎯 概要
wt profile の空白入り名称で ArgList split が壊れる問題を GUID 優先で回避。

### ✅ テスト結果
- CI SUCCESS (commit 400ac1c)

---

## [v3.2.47] - 2026-04-20 — wt profile を動的検出

### 🎯 概要
"PowerShell version 7" / "PowerShell 7" 両対応の wt profile 動的検出を実装。

### ✅ テスト結果
- CI SUCCESS (commit 9be5999)

---

## [v3.2.46] - 2026-04-20 — Watch-ClaudeLog spawn タブアイコンを PowerShell 化

### 🎯 概要
Watch-ClaudeLog.ps1 で `wt -p PowerShell` を使用してタブアイコンを PowerShell に統一。

### ✅ テスト結果
- CI SUCCESS (commit 10289ec)

---

## [v3.2.45] - 2026-04-20 — scripts/templates/claudeos/ 削除・Claude/templates/claudeos/ に一本化

### 🎯 概要
旧 `scripts/templates/claudeos/` を削除し `Claude/templates/claudeos/` に統一。

### ✅ テスト結果
- CI SUCCESS (commit 7d9f6a2)

---

## [v3.2.44] - 2026-04-20 — Claude/templates/claudeos/ 全体を .claude/claudeos/ に deploy

### 🎯 概要
~345 ファイル (agents/skills/commands/rules 等) を `scp -r` で一括転送する bulk sync を実装。

### ✅ テスト結果
- CI SUCCESS (commit 6938bb2)

---

## [v3.2.43] - 2026-04-20 — scripts/templates/CLAUDE-Back20260331.md 削除

### 🎯 概要
v2.4.0 時点の死蔵バックアップファイルを削除。

### ✅ テスト結果
- CI SUCCESS (commit 08c1907)

---

## [v3.2.42] - 2026-04-20 — pwsh 7 強制 + Start-Job UTF-8 化

### 🎯 概要
pwsh 7 を強制起動し、Start-Job での UTF-8 出力を保証してタブ表示/文字化けを修正。

### ✅ テスト結果
- CI SUCCESS (commit a25d52d)

---

## [v3.2.41] - 2026-04-20 — Watch-ClaudeLog.ps1 マルチ発火対応

### 🎯 概要
`tail -F` を `Start-Job` 化してマルチ発火・多重起動問題を解消。

### ✅ テスト結果
- CI SUCCESS (commit 38cfe89)

---

## [v3.2.40] - 2026-04-20 — cron-launcher PATH 注入 + SAFE_PROJECT 末尾アンダースコア解消

### 🎯 概要
cron-launcher.sh に PATH を注入してコマンド未検出を修正。SAFE_PROJECT の末尾アンダースコアを解消。

### ✅ テスト結果
- CI SUCCESS (commit b5ef8b1)

---

## [v3.2.39] - 2026-04-19 — Session Info タブ 3 点修正 (残り時間表示 / 凍結耐性 / UI 補足)

### 🎯 概要

cron 監視タブ群で表面化していた 3 種類の UX 問題を同時修正。

1. **残り時間表示の +1h ズレ**（ロジックバグ）: `Format-Duration` の `[int]$Span.TotalHours` が .NET の銀行丸め（`MidpointRounding.ToEven`）により時間成分を繰り上げ、「経過 00:04:06 + 残り 05:55:53 = 6h」のように合計が `作業時間`（5h）と一致しない現象。`[int][Math]::Floor($Span.TotalHours)` で明示的切り捨てに変更。v3.2.38 の TZ 修正でも残存していた独立バグ。
2. **クリック凍結**（UX 問題）: Windows conhost の QuickEdit モードがタブ内の範囲選択で stdout をブロックし、監視タブが固まったように見える現象。`kernel32!SetConsoleMode` を P/Invoke 経由で呼び `ENABLE_QUICK_EDIT_MODE (0x40)` をクリア、`ENABLE_EXTENDED_FLAGS (0x80)` を付与。Windows Terminal の独自選択機構は conhost フラグ非依存なのでコピペ操作は従来通り動作する。
3. **復旧操作の可視化**（UI 補足）: `Ctrl+C でこのタブを閉じる` 行の下に `Enterキーで更新可能` と **動的生成した再起動コマンド** を常時表示。`$PSCommandPath` + 実行時パラメータから自動生成するため、別セッション / 別プロジェクトでも常に正しい再起動コマンドが出る。凍結時のフォールバック手段を画面内に常設することで「ドキュメントを探し回らない運用 UI」を実現。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/tools/Watch-SessionInfoSSH.ps1` | `Format-Duration` / `作業時間` 行: `[int]` → `[int][Math]::Floor` / QuickEdit 無効化 P/Invoke / `Enterキーで更新可能` + 再起動コマンド表示 |
| `scripts/tools/Watch-SessionInfo.ps1` | 同上（非 SSH 版） |
| `scripts/tools/Watch-ClaudeLog.ps1` | QuickEdit 無効化 P/Invoke 追加 |
| `README.md` | バージョン v3.2.37 → v3.2.39、主要箇所のテスト件数 650 → 680 件に更新 |
| `CHANGELOG.md` | v3.2.39 エントリ追加 |
| `TASKS.md` | エントリ 54 (v3.2.39) 追加 |

### ✅ テスト結果

- 680/680 PASS (Pester, 139s)
- PSScriptAnalyzer 警告 0 件（空 catch は `$null = $_` で明示的無視を表現）

### 📝 補足: v3.2.38 の CHANGELOG ギャップ

本エントリ作成時、v3.2.38 の CHANGELOG エントリが欠落していることを検出（TASKS.md エントリ 53 は存在）。スコープ外のため本 commit では backfill せず、別途 docs(changelog): v3.2.38 backfill として対応候補とする。

---

## [v3.2.37] - 2026-04-18 — scripts/lib 全ファイル UTF-8 BOM 追加 (PSScriptAnalyzer 警告ゼロ回復)

### 🎯 概要

v3.2.35 の AgentTeams 分割で生成した 3 ファイルを含む `scripts/lib/` 配下 11 ファイルに UTF-8 BOM が欠落しており `PSUseBOMForUnicodeEncodedFile` 警告が 11 件発生していた。BOM を追加して警告 0 件を回復。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/lib/AgentCapabilityMatrix.ps1` | UTF-8 BOM 追加 |
| `scripts/lib/AgentDefinition.ps1` | UTF-8 BOM 追加 |
| `scripts/lib/AgentTeamBuilder.ps1` | UTF-8 BOM 追加 |
| `scripts/lib/AgentTeams.psm1` | UTF-8 BOM 追加 |
| `scripts/lib/Config.psm1` | UTF-8 BOM 追加 |
| `scripts/lib/ConfigLoader.ps1` | UTF-8 BOM 追加 |
| `scripts/lib/ConfigSchema.ps1` | UTF-8 BOM 追加 |
| `scripts/lib/LauncherCommon.psm1` | UTF-8 BOM 追加 |
| `scripts/lib/RecentProjects.ps1` | UTF-8 BOM 追加 |
| `scripts/lib/SessionLogger.ps1` | UTF-8 BOM 追加 |
| `scripts/lib/TemplateSyncManager.ps1` | UTF-8 BOM 追加 |

### ✅ テスト結果

- 650/650 PASS
- PSScriptAnalyzer 警告 0 件

---

## [v3.2.36] - 2026-04-18 — Watch-SessionInfoSSH TZ オフセット不整合修正

### 🎯 概要

Linux の `end_time_planned` フィールドが TZ オフセット不整合（`+09:00` vs `+08:00`）で UTC ベース演算が 1 時間ズレ、残り時間が実際より 1 時間多く表示される問題を修正。`start_time + max_duration_minutes`（整数演算）を信頼できる終了時刻として採用し、`ToLocalTime()` で Windows ローカル時刻に統一表示する。5 分超のズレを検出した場合に警告行を表示するドリフト検出機能も追加。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/tools/Watch-SessionInfoSSH.ps1` | `$remaining` を `start + duration - now` で再計算 / `ToLocalTime()` 表示統一 / ドリフト検出警告追加 |
| `README.md` | バージョン v3.2.36 / テスト件数 650 件に更新 |
| `TASKS.md` | エントリ 50 (v3.2.35) / 51 (v3.2.36) 追加 |

### ✅ テスト結果

- 650/650 PASS
- PSScriptAnalyzer 警告 0 件

---

## [v3.2.35] - 2026-04-18 — AgentTeams.psm1 モノリス分割

### 🎯 概要

506 行のモノリシックな `AgentTeams.psm1` を責務ごとに 3 ファイルに分割し、薄い dot-source オーケストレーターに変換。依存順序を `AgentDefinition.ps1 → AgentTeamBuilder.ps1 → AgentCapabilityMatrix.ps1` で明示。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/lib/AgentTeams.psm1` | 18 行の薄い dot-source オーケストレーターに書き換え |
| `scripts/lib/AgentDefinition.ps1` | 新規追加 — CoreRoles / TaskTypePatterns / Import-AgentDefinition / Get-TaskTypeAnalysis / Get-BacklogRuleMatch |
| `scripts/lib/AgentTeamBuilder.ps1` | 新規追加 — New-AgentTeam / Format-AgentTeamDiscussion / Show-AgentTeamComposition / Get-AgentTeamReport / Show-AgentTeamReport |
| `scripts/lib/AgentCapabilityMatrix.ps1` | 新規追加 — Get-AgentCapabilityMatrix / Show-AgentCapabilityMatrix / Get-AgentQuickStatus |

### ✅ テスト結果

- 650/650 PASS
- PSScriptAnalyzer 警告 0 件

---

## [v3.2.34] - 2026-04-18 — Phase 4 テストファイル UTF-8 BOM 追加 (PSScriptAnalyzer 警告解消)

### 🎯 概要

v3.2.33 で追加した Phase 4 ユニットテストファイル 3 件 (`AgentTeams.Tests.ps1` / `ArchitectureCheck.Tests.ps1` / `IssueSyncManager.Tests.ps1`) に UTF-8 BOM が欠落しており、`PSUseBOMForUnicodeEncodedFile` 警告が 3 件発生していた。BOM を追加して警告 0 件を回復。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `tests/unit/AgentTeams.Tests.ps1` | UTF-8 BOM 追加 |
| `tests/unit/ArchitectureCheck.Tests.ps1` | UTF-8 BOM 追加 |
| `tests/unit/IssueSyncManager.Tests.ps1` | UTF-8 BOM 追加 |
| `CHANGELOG.md` | v3.2.33 / v3.2.34 エントリ追加 |
| `README.md` | バージョン v3.2.34 / テスト件数 650 件 更新 |
| `TASKS.md` | エントリ 49 追加 |

### ✅ テスト結果

- 650/650 PASS
- PSScriptAnalyzer 警告 0 件

---

## [v3.2.33] - 2026-04-18 — Phase 4 ユニットテスト追加 + SelfEvolution バグ修正 (Issue #183 + #184)

### 🎯 概要

未テスト lib モジュール解消 Phase 4。AgentTeams / IssueSyncManager / SelfEvolution / WorktreeManager / ArchitectureCheck の 5 モジュールに計 81 テストを追加。合計 650/650 PASS。また `Save-EvolutionRecord` が明示 `$StorePath` 指定時にディレクトリ未作成のまま `Set-Content` を呼び失敗するバグを修正。`.gitleaks.toml` を追加してテストフィクスチャの false positive を抑制。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `tests/unit/AgentTeams.Tests.ps1` | 新規追加 — 19 テスト |
| `tests/unit/IssueSyncManager.Tests.ps1` | 新規追加 — 24 テスト |
| `tests/unit/SelfEvolution.Tests.ps1` | 新規追加 — 17 テスト |
| `tests/unit/WorktreeManager.Tests.ps1` | 新規追加 — 3 テスト |
| `tests/unit/ArchitectureCheck.Tests.ps1` | 新規追加 — 18 テスト |
| `scripts/lib/SelfEvolution.psm1` | `Save-EvolutionRecord`: `$StorePath` 指定時も `Get-EvolutionStorePath` を経由する 2 ステップ変数割り当てに修正 |
| `.gitleaks.toml` | 新規追加 — `ArchitectureCheck.Tests.ps1` フィクスチャへの allowlist |
| `TASKS.md` | エントリ 48 追加 |

### ✅ テスト結果

- 650/650 PASS (既存 569 + 新規 81)
- PSScriptAnalyzer 警告 0 件 → 警告 3 件 (BOM 欠落。v3.2.34 で解消)

---

## [v3.2.32] - 2026-04-18 — Watch-ClaudeLog tmux ゴーストセッション修正 (Issue #188)

### 🎯 概要

`Open-TmuxAttachTab` で `tmux new-session -A -s` を使っていたため、
`finalize()` がセッションを kill した後に Tab 2 の SSH 接続が遅れて到達すると
空のゴーストセッションが作成される問題を修正。
`tmux attach-session -t` に変更することで、セッション不在時はエラー終了し
ゴーストセッションが生まれなくなる。

### 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `scripts/tools/Watch-ClaudeLog.ps1` | `Open-TmuxAttachTab`: `new-session -A -s` → `attach-session -t` |
| `TASKS.md` | エントリ 47 追加 |

### CI

- 569/569 PASS
- PSScriptAnalyzer 警告 0 件

## [v3.2.31] - 2026-04-18 — Watch-ClaudeLog 起動時セッション検出修正 + cron-launcher tmux -e 修正 (Issue #185 + #186)

### 🎯 概要

Watch-ClaudeLog.ps1 の起動時セッション検出漏れ (Issue #185) と cron-launcher.sh の tmux env var 継承バグ (Issue #186) を修正。本番サーバー反映済み。569/569 PASS 継続。

### 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `scripts/tools/Watch-ClaudeLog.ps1` | 起動時に最新ログが15分以内なら即監視開始 (`TryParseExact` 使用) |
| `Claude/templates/linux/cron-launcher.sh` | `tmux new-session -e` で env var 明示渡し + PROMPT_ARG サイドカーファイル化 |
| `TASKS.md` | エントリ 46 追加 |

### CI

- 569/569 PASS
- PSScriptAnalyzer 警告 0 件

## [v3.2.30] - 2026-04-18 — Phase 3 ユニットテスト追加 — StatuslineManager / McpHealthCheck (Issue #184)

### 🎯 概要

未テスト lib モジュール解消 Phase 3。`StatuslineManager.psm1` `Get-GlobalStatusLineConfig` 7 テスト ($TestDrive 隔離)、`McpHealthCheck.psm1` `ConvertTo-McpProcessArgumentString` 6 テスト (InModuleScope でプライベート関数を直接検証)。既存 556 + 新規 13 = 569 PASS。PSScriptAnalyzer 警告 0 件継続。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `tests/unit/StatuslineManager.Tests.ps1` | 新規追加 — 7 テスト (Get-GlobalStatusLineConfig: found/path/statusLine/throw 境界値) |
| `tests/unit/McpHealthCheck.Tests.ps1` | 新規追加 — 6 テスト (ConvertTo-McpProcessArgumentString: 空/単純/スペース/ダブルクォート/混合) |

### ✅ テスト結果

- CI: 569/569 PASS
- PSScriptAnalyzer: 0 warnings
- STABLE N=2

---

## [v3.2.29] - 2026-04-18 — Phase 2 ユニットテスト追加 — MenuCommon / SSHHelper / SessionTabManager (Issue #183)

### 🎯 概要

未テスト lib モジュール解消 Phase 2。`MenuCommon.psm1` 純粋関数 3 種 19 テスト、`SSHHelper.psm1` `ConvertTo-EscapedSSHArgument` 7 テスト、`SessionTabManager.psm1` `Get-SessionDir` / `New-SessionId` / `New-SessionInfo` / `Get-ActiveSession` 等 15 テストを追加。既存 515 + 新規 41 = 556 PASS。PSScriptAnalyzer 警告 0 件継続。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `tests/unit/MenuCommon.Tests.ps1` | 新規追加 — 19 テスト (ConvertTo-MenuRecentToolFilter / ConvertTo-MenuRecentSortMode / Get-MenuRecentFilterSummary) |
| `tests/unit/SSHHelper.Tests.ps1` | 新規追加 — 7 テスト (ConvertTo-EscapedSSHArgument・エスケープ境界値) |
| `tests/unit/SessionTabManager.Tests.ps1` | 新規追加 — 15 テスト (Get-SessionDir / New-SessionId / New-SessionInfo / Save-SessionInfo / Get-SessionInfo / Get-ActiveSession) |

### ✅ テスト結果

- CI: 556/556 PASS
- PSScriptAnalyzer: 0 warnings
- STABLE N=2

---

## [v3.2.28] - 2026-04-18 — CronManager / LogManager ユニットテスト追加 (Issue #182)

### 🎯 概要

未テスト lib モジュール解消 Phase 1。`CronManager.psm1` 純粋ロジック関数 4 種 + `Get-ClaudeOSCronEntry` (Mock 使用) を 27 テスト、`LogManager.psm1` `Get-LogSummary` / `Invoke-LogRotation` を 11 テストでカバー。既存 477 + 新規 38 = 515 PASS。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `tests/unit/CronManager.Tests.ps1` | 新規追加 — 27 テスト (Format-CronExpression / Get-DayOfWeekLabel / New-CronEntryId / Format-CronEntryForDisplay / Get-ClaudeOSCronEntry) |
| `tests/unit/LogManager.Tests.ps1` | 新規追加 — 11 テスト (Get-LogSummary / Invoke-LogRotation) |

### ✅ テスト結果

- CI: 515/515 PASS
- STABLE N=2

---

## [v3.2.27] - 2026-04-18 — PSScriptAnalyzer 警告ゼロ達成 (BOM + UnusedParam 修正)

### 🎯 概要

v3.2.17 追加の `Watch-ClaudeLog.ps1` / `Watch-SessionInfoSSH.ps1` に UTF-8 BOM を追加（`PSUseBOMForUnicodeEncodedFile` 残存 2 件解消）。
`Diagnostics.Tests.ps1` の Pester Mock `param()` 宣言パラメータに `$null = $Param` 参照を追加し `PSReviewUnusedParameter` 12 件を解消。
`PSAvoidUsingWriteHost` を除く全警告がゼロになった。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/tools/Watch-ClaudeLog.ps1` | UTF-8 BOM 追加 |
| `scripts/tools/Watch-SessionInfoSSH.ps1` | UTF-8 BOM 追加 |
| `tests/integration/Diagnostics.Tests.ps1` | Mock param() に $null = $Param 追加 (12 箇所) |

### ✅ Verify

- PSScriptAnalyzer: 0 警告 (WriteHost 除く)
- CI: 477/477 PASS
- STABLE N=2 達成

---

## [v3.2.26] - 2026-04-18 — tests/ サブディレクトリ分類 — unit / integration / smoke

### 🎯 概要

17 テストファイルを `tests/unit/`・`tests/integration/`・`tests/smoke/` へ分類（外部レビュー #11 対応）。
`$PSScriptRoot` 基準のパス参照をディレクトリ深度増加に合わせて修正。
`tests/README.md` で分類基準を文書化。Pester 5.x の再帰検索により CI 設定変更不要。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `tests/unit/` | Config / ErrorHandler / LauncherCommon / MessageBus / TokenBudget — 5 ファイル移動 |
| `tests/integration/` | AgentTeams / ArchitectureCheck / ClaudeOSPlugin / Diagnostics / IssueSyncManager / McpHealthCheck / SelfEvolution / SSHHelper / StartScripts / Sync-Issues / WorktreeManager — 11 ファイル移動 |
| `tests/smoke/` | E2E — 1 ファイル移動 |
| `tests/README.md` | 分類基準・ファイル一覧・実行方法を文書化（新規作成） |
| 各テストファイル | `$PSScriptRoot` → `Split-Path -Parent (Split-Path -Parent $PSScriptRoot)` に修正 |

### ✅ Verify

- CI: 477/477 PASS
- STABLE N=2 達成

---

## [v3.2.25] - 2026-04-18 — Loop レポート reports/ 統合 — build / improve 出力先統一

### 🎯 概要

`reports/README.md` で「別 Issue」として残されていた Build / Improve ループの出力先を `reports/` へ統合。
全 4 ループ（monitor / build / verify / improve）の Output 節が `reports/.loop-*.md` に統一された。
外部コードレビュー評価 #17 の独立 Issue 候補を完全解消（Issue #178）。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `.claude/claudeos/loops/build-loop.md` | Output 節を `reports/.loop-build-report.md` に更新 |
| `.claude/claudeos/loops/improve-loop.md` | Output 節を `reports/.loop-improve-report.md` に更新 |
| `Claude/templates/claudeos/loops/build-loop.md` | Output 節追加（テンプレ同期） |
| `Claude/templates/claudeos/loops/improve-loop.md` | Output 節追加（テンプレ同期） |
| `reports/README.md` | build / improve 行を ⏳ → ✅ に更新、完了注記追加 |

### ✅ Verify

- CI: test-and-validate / PSScriptAnalyzer / Secrets scan — 全 pass
- STABLE N=2 達成

---

## [v3.2.24] - 2026-04-18 — Memory MCP 退避機能 + AgentTeams ドキュメントクリーンアップ

### 🎯 概要

`/compact` 実行前にセッション状態を Memory MCP へ退避する PreCompact フック (`memory-mcp-evacuation.md`) を実装。
Node.js 側 (`pre-compact.js`) には evacuation JSON 書き出し機能を追加し、MCP 非接続環境でも再開情報を保全。
`docs/common/08_AgentTeams対応表.md` の `## 未実装機能` セクションから実装済み項目を削除し、
自動同期スクリプト (`Sync-AgentTeamsBacklog.ps1`) が不要なバックログエントリを生成しなくなった。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `.claude/claudeos/hooks/memory-mcp-evacuation.md` | 新規 — PreCompact フック命令書 (Memory MCP エンティティ書き込み手順) |
| `.claude/claudeos/scripts/hooks/pre-compact.js` | 拡張 — `writeEvacuationSummary()` 追加、`evacuation-latest.json` を snapshots/ へ書き出し |
| `.claude/claudeos/hooks/hooks.json` | `PreCompact` セクション追加 — `memory-mcp-evacuation` フック登録 |
| `docs/common/08_AgentTeams対応表.md` | `## 未実装機能` クリーンアップ — 完了済み 2 項目を実装済み注記へ移動 |

### ✅ Verify

- CI: test-and-validate / PSScriptAnalyzer / Secrets scan — 全 pass
- Memory MCP 未接続環境: Step 1 で no-op 終了（セッション継続）
- `evacuation-latest.json` 書き出し: pre-compact.js 単体動作確認済み

---

## [v3.2.23] - 2026-04-18 — cron-launcher.sh SIGTTOU 停止バグ修正

### 🎯 概要

cron 経由で起動した Claude が tmux セッション内で `Tl`（SIGTTOU 停止）状態になり実行されないバグを修正。
2 件の根本原因を特定し、本番サーバーで検証済みの修正をリポジトリテンプレートへ同期。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `Claude/templates/linux/cron-launcher.sh` | `timeout --foreground` 追加 (3 箇所) — GNU timeout の `setpgid(0,0)` を無効化し SIGTTOU を防止 |
| `Claude/templates/linux/cron-launcher.sh` | `tmux pipe-pane` 2 行削除 — PTY ストリーム横断による DA クエリ応答破壊を修正 |

### 🐛 根本原因

| バグ | 原因 | 修正 |
|---|---|---|
| `Tl` 停止 (SIGTTOU) | `timeout` が `setpgid(0,0)` で子プロセスを新 PGID へ移動 → Claude が前景グループ外になり `tcsetattr()` 呼出で SIGTTOU 受信 | `timeout --foreground` で `setpgid(0,0)` 抑制 |
| TUI 初期化失敗 | `pipe-pane` が PTY ストリームを横断し DA クエリへの応答を破壊 | `pipe-pane` 行を削除 |

### ✅ Verify

- CI: test-and-validate / PSScriptAnalyzer / Secrets scan / CodeRabbit — 全 pass
- 本番サーバー: Claude PID `Tl` → `Sl+` 遷移確認済み

---

## [v3.2.22] - 2026-04-17 — state.json.example スキーマ整合 / CI example バリデーション

### 🎯 概要

v3.2.21 で拡張した `state.schema.json` に対して `state.json.example` の構造・型が不整合だった
6 箇所を修正。CI に example → schema バリデーションステップを追加し、再発を防止。

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `state.json.example` | `message_bus` をフラットキーからネスト構造に修正 / `debug.debug_mode` を `"normal"` → `false` (boolean) / `debug.last_failure_category` 等 3 フィールドを `"none"` → `null` / `_note` バージョン表記を "v8.2" → "v8" に修正 |
| `scripts/validate-state-example.js` | 新規。`state.json.example` を `state.schema.json` に対して型・構造チェック (外部依存なし) |
| `.github/workflows/ci.yml` | "Validate State Example Against Schema" ステップ追加 |
| `TASKS.md` | v3.2.19/v3.2.20/v3.2.21 を [DONE] に更新、v3.2.22 エントリ追加 |

### ✅ Verify

- `node scripts/validate-state-example.js`: PASSED
- `node scripts/check-doc-versions.js`: PASSED

---

## [v3.2.21] - 2026-04-17 — ドキュメント品質 / スキーマ拡張 / README 自動整合

### 🎯 概要

外部コードレビュー評価 (2026-04-17) の中期対応 3 項目を実装。
state.schema.json を拡張、README 統計の自動注入スクリプトを追加し、
CI でのドリフト検出を強化。

### 🔧 変更対象

| ファイル | 変更内容 | 対応評価項目 |
|---|---|---|
| `state.schema.json` | `frontier / message_bus / learning / debug / onboarding / improvement` ブロック追加。title を "ClaudeOS v8" に整合 | #35 |
| `docs/common/18_ARCHITECTURE.md` | Agent 数を 17 → 25 体に修正 | #9 |
| `scripts/update-readme-stats.js` | 新規。CHANGELOG 最新バージョン / Agent 数 / コマンド数を README.md に自動注入 | #2 |
| `.github/workflows/ci.yml` | "Check README Stats Up-to-date" ステップ追加（スクリプト実行後 git diff が残れば CI 失敗） | #2 |

### ✅ Verify

- `node scripts/update-readme-stats.js`: README already up-to-date — no changes written
- `node scripts/check-doc-versions.js`: PASSED

---

## [v3.2.20] - 2026-04-17 — CI テスト出力先移行 / .codex テンプレ化 / ドキュメントドリフト修正

### 🎯 概要

外部コードレビュー評価 (2026-04-17) の即時対応 3 項目を実装。
testResults.xml を reports/ へ移行、.codex/config.toml を .gitignore 対象化、
README/ONBOARDING のバージョン・エージェント数不一致を修正。

### 🔧 変更対象

| ファイル | 変更内容 | 対応評価項目 |
|---|---|---|
| `.github/workflows/ci.yml` | Pester を PesterConfiguration で `reports/testResults.xml` に出力、"Check Doc Version Consistency" ステップ追加 | #17, #2 |
| `scripts/check-doc-versions.js` | 新規。CHANGELOG バージョン / Agent 数を README と比較して不一致を CI で検出 | #2 |
| `.codex/config.toml.example` | 新規。共有テンプレートとして設計（パスワード・個人設定なし） | #32 |
| `.codex/config.toml` | `git rm --cached` で追跡解除 + `.gitignore` 追加 | #32 |
| `README.md` | バージョン v3.2.5 → v3.2.19、Agents 17 → 25 体、Mermaid・カーネル行の数値整合 | #2 |
| `ONBOARDING.md` | state.json 未存在記述を実値に更新、Agent 数 37 → 25 体、git log を v3.2.8〜v3.2.19 に更新 | #2 |
| `reports/README.md` | testResults.xml / playwright スクリーンショットの移行状況を追記 | #17 |

### ✅ Verify

- `node scripts/check-doc-versions.js`: PASSED — v3.2.19 / 25 agents / 34 commands

---

## [v3.2.19] - 2026-04-17 — 3 タブ監視 品質向上 (外部レビュー追加指摘 3 件対応)

### 🎯 概要

v3.2.17 で導入した 3 タブ監視構成に対して、2026-04-17 受領の外部レビュー（15 改善アイデア中）から設計欠陥に該当する 3 件を修正。

### 🔧 変更対象

| ファイル | 変更内容 | 対応評価項目 |
|---|---|---|
| `scripts/tools/Watch-ClaudeLog.ps1` (L142, L208) | `tmux attach -t` → `tmux new-session -A -s` (attach-or-create)、`tail -f` → `tail -F` (inode 変化追従 = ログローテーション耐性) | #1, #3 |
| `scripts/tools/Watch-SessionInfoSSH.ps1` (L53-) | `Get-RemoteSession` を 2 段リトライ化、戻り値を `{Session, Status, Raw}` 構造体に拡張。書き込み途中 JSON の破損時は 200ms 後に再取得 | #5 |
| `scripts/tools/Watch-SessionInfoSSH.ps1` (main loop) | 前回有効値キャッシュ (`$lastValidSession` / `$lastValidReadAt`) + `[STALE]` 表示で破損・消失時も前回値を継続表示 | #5, #11 |
| `scripts/tools/Watch-SessionInfoSSH.ps1` (Show-SessionFrame) | `LastValidReadAt` + `IsStale` を引数追加、stale 秒数と最終有効読取時刻を併記 | #11 |

### 📊 対応方針

評価 15 項目のうち、実装確認（grep）で **既対応判明** した項目:
- #4 引数化・設定化: `$SshTarget` / `$tmuxSession` / `$LinuxHost` / `$LinuxUser` / `$SessionsDir` 全パラメータ化済 (v3.2.17)
- #7 タブタイトル明示: `Claude-Live-Log` / `Claude-UI` / `Session-Info` 付与済 (v3.2.17)
- #9 失敗分離 (部分): `if ($wtExe)` ガード + 各 tab 独立 `Start-Process` 済

残 10 項目（exit code 表示、疎通事前チェック、タブ色・アイコン、マルチホスト等）は P3 backlog として別 Issue 起票予定。

### ✅ Verify

- `Invoke-Pester` Passed: **477** / Failed: **0**
- `Invoke-ScriptAnalyzer -Severity Error`: 0 件

---

## [v3.2.18] - 2026-04-17 — 外部コードレビュー指摘 5 件対応 (Quick-wins)

### 🎯 概要

外部コードレビュー (2026-04-17) で受領した 60 項目の改善提案のうち、影響範囲が小さく
即対応可能な 5 カテゴリ（評価項目 #6, #9, #17, #21, #32, #34, #39）を 1 PR で束ねて消化。

### 🔧 変更対象

| ファイル | 変更内容 | 対応評価項目 |
|---|---|---|
| `reports/README.md` | 新規。`.loop-*.md` 等の揮発性レポート集約先を定義 | #17 |
| `reports/.loop-monitor-report.md` | ルート直下から移動（未追跡） | #17 |
| `.gitignore` | `reports/.loop-*.md`, `reports/*.log`, `reports/*.xml` 追加 | #17 |
| `.claude/claudeos/loops/monitor-loop.md` | Output パスを `reports/.loop-monitor-report.md` に更新 | #17 |
| `scripts/templates/claudeos/loops/monitor-loop.md` | 同上（配布用テンプレ側も同期） | #17 |
| `Claude/README.md` | 新規。`.claude/` / `Claude/` / `docs/claude/` の役割差分明記 | #6 |
| `.codex/config.toml` | 旧 profiles/features/shell_environment_policy 削除、`[shell]` で `pwsh -NoLogo -NoProfile -NonInteractive` 固定 | #32 |
| `README.md` | `## 標準コマンド` セクション追加（lint / test / build / security の 4 動詞集約） | #21 |
| `docs/common/18_ARCHITECTURE.md` | 新規。scripts 依存方向 + Claude/Codex ディレクトリ差分 + 用語集を 1 ページ統合 | #9, #34, #39 |

### 📊 対応スコア

- 60 項目中 **9 項目対応** (15%) — 既対応 9 項目と合わせて計 18 項目 (30%) が解消済
- 残項目のうち中期対応 18 / 判断要 16 / 不採用候補 5 は別 Issue / PR で順次処理

### 🚫 スコープ外

- 評価 #19 `testResults.xml` の `reports/` 移動は Pester `-CI` スイッチと ci.yml の両方を調整する必要があるため、別 Issue に切り出し
- 評価 #11 `tests/` の unit/integration/smoke 分類は 17 ファイル の仕分けを要するため別 PR
- 評価 #15 `state.json` JSON Schema は既存 (`state.schema.json`) により対応済

### ✅ Verify

- `Invoke-Pester` Passed: **477** / Failed: **0**
- `Invoke-ScriptAnalyzer -Severity Error`: 0 件
- STABLE N=2 達成予定

---

## [v3.2.17] - 2026-04-17 — 3タブ監視構成 + tmux UI 統合

### 🎯 概要

cron 発火した ClaudeCode セッションを Windows Terminal から 3 タブでリアルタイム監視できる構成を実装：

- **Tab①** ログ監視 (`Watch-ClaudeLog.ps1`): SSH `tail -f` で cron ログをリアルタイム表示
- **Tab②** Claude UI (`tmux attach`): cron-launcher 側で tmux 内に Claude を TTY あり起動、`ssh -t tmux attach` で対話 UI を Windows から閲覧可能
- **Tab③** Session Info (`Watch-SessionInfoSSH.ps1`): session.json を SSH ポーリングで残り時間・status をリアルタイム更新

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/tools/Watch-ClaudeLog.ps1` | 新規。cron ログ検出 + Tab②③ 自動展開 |
| `scripts/tools/Watch-SessionInfoSSH.ps1` | 新規。session.json SSH ポーリング表示 |
| `Claude/templates/linux/cron-launcher.sh` | tmux new-session で Claude を TTY あり実行、wrapper script で引数安全渡し、`tmux pipe-pane` でログも同時書き込み、`tmux wait-for` で同期 |
| `scripts/main/Start-Menu.ps1` | 項目 14「Claude ログ監視タブを開く」追加 |
| `config/config.json.template` | `linuxUser` フィールド追加（default: kensan） |

### 🔐 CodeRabbit / Codex 指摘対応

- SSH ユーザー名を `config.linuxUser` からパラメータ化（ハードコード解消）
- DateTimeOffset でタイムゾーン情報を保持（Get-Date ローカルタイム問題解消）
- wrapper script の `set -euo pipefail` を除去 — claude 非0終了でも `tmux wait-for -S` 到達保証

### ✅ 検証結果

- CI: test-and-validate / PSScriptAnalyzer / gitleaks / CodeRabbit 全 SUCCESS
- Linux デプロイ: `/home/kensan/.claudeos/cron-launcher.sh` v3.2.16 確認
- tmux 3.4 インストール確認済み

---

## [v3.2.14] - 2026-04-17 — PSProvideCommentHelp 警告 85 件解消

### 🎯 概要

- 9 ファイル 85 関数に `.SYNOPSIS` コメントブロックを追加
- PSScriptAnalyzer `PSProvideCommentHelp` 警告を 0 件へ解消

### 🔧 変更対象

| ファイル | 追加件数 |
|---|---|
| `scripts/lib/LauncherCommon.psm1` | 41 |
| `scripts/lib/CronManager.psm1` | 9 |
| `scripts/lib/AgentTeams.psm1` | 8 |
| `scripts/lib/SessionTabManager.psm1` | 8 |
| `scripts/lib/LogManager.psm1` | 5 |
| `scripts/lib/McpHealthCheck.psm1` | 5 |
| `scripts/lib/Config.psm1` | 4 |
| `scripts/lib/MenuCommon.psm1` | 3 |
| `scripts/lib/StatuslineManager.psm1` | 2 |

### ✅ 検証結果

- `Invoke-ScriptAnalyzer -IncludeRule PSProvideCommentHelp` = **0 件**
- `Invoke-Pester` Passed: **477** / Failed: **0**

---

## [v3.2.13] - 2026-04-17 — PSAvoidUsingPositionalParameters 残存 1 件解消 + CLAUDE.md v8.3

### 🎯 概要

- `Test-ArchitectureCheck.ps1:16` の `Join-Path` 位置パラメーター警告残存 1 件を修正
- CLAUDE.md v8.3: Auto mode 操作手順（Shift+Tab）と Response length calibration 指針を追加

### 🔧 変更対象

| ファイル | 変更内容 |
|---|---|
| `scripts/test/Test-ArchitectureCheck.ps1` | `Join-Path` → `-AdditionalChildPath` 名前付き引数へ変換 |
| `CLAUDE.md` | §3 Auto mode Shift+Tab 操作手順テーブル追加 / §24.1 Response length calibration 指針追加 |

### ✅ 検証結果

- `Invoke-ScriptAnalyzer -IncludeRule PSAvoidUsingPositionalParameters` = **0 件**
- `Invoke-Pester` Passed: **477** / Failed: **0**

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
