# 18. アーキテクチャ要約 — 依存方向 / ディレクトリ差分 / 用語集

本書は外部コードレビュー評価 (2026-04-17) の改善項目 #9 (scripts 依存方向)、
#34 (`.claude/.codex` 差分表)、#39 (用語集) を 1 ページに統合する参照ドキュメントです。
初見メンバーが **10 分で全体像を掴める** 入口として機能することを目的とします。

> 規範 (MUST): `CLAUDE.md` / `AGENTS.md` / `.claude/claudeos/system/*`
> 参照 (INFO): 本書 / `docs/common/` 配下

## 1. `scripts/` の依存方向

PowerShell スクリプトの依存は **一方向** に固定します。逆方向の import は
禁止です（循環依存防止）。

```
  [ 外部入口 ]
     main/          <---- ユーザー / cron / CI から直接呼ばれる
       │
       ▼
     tools/         <---- main から呼ばれる運用補助（Update-TASKS, Sync-Issues 等）
       │
       ▼
     lib/           <---- 関数ライブラリ（*.psm1）。tools / main / test が import
       │
       ▲
     helpers/       <---- 初期化ヘルパ（Start-ClaudeOS から利用）
     setup/         <---- ワンタイムセットアップ（主に初回実行）
     templates/     <---- 他プロジェクト配布用テンプレ（実行ロジックを置かない）
     test/          <---- 診断スクリプト（Test-AllTools / Test-McpHealth 等）
```

### 層別の役割と代表ファイル

| 層 | 役割 | 代表ファイル |
|---|---|---|
| `main/` | 公開 API 相当の入口。ユーザーが `.\scripts\main\Start-XXX.ps1` で直接叩く | `Start-ClaudeOS.ps1`, `Start-Menu.ps1`, `Start-ClaudeCode.ps1` |
| `tools/` | 運用補助スクリプト。main からも単独実行からも呼べる | `Update-TASKS.ps1`, `Sync-Issues.ps1`, `Watch-ClaudeLog.ps1` |
| `lib/` | 再利用可能な関数モジュール。外部依存最小 | `AgentTeams.psm1`, `Config.psm1`, `WorktreeManager.psm1` 等 17 個 |
| `helpers/` | 初期化支援（Boot Sequence Step 3 など） | Memory 初期化系 |
| `setup/` | 一度きりのセットアップ作業 | 初期 config 生成 |
| `templates/` | **実行ロジック禁止**。Claude/ と合わせて配布テンプレ | `claudeos/` 雛形 |
| `test/` | 診断スクリプト（Pester ではなく CLI 診断） | `Test-AllTools.ps1`, `Test-McpHealth.ps1` |

### 禁則

- `lib/*.psm1` から `main/` / `tools/` を呼ばない
- `templates/` 配下から他層の関数を import しない（配布先で未解決になる）
- `main/` 同士の相互呼び出しは避ける（Start-Menu から Start-ClaudeOS は OK、逆は NG）

## 2. Claude / Codex 関連ディレクトリ差分

3 系統 × 3 層で計 9 パターンあります。

| ディレクトリ | 所属 | 役割 | 配布対象 |
|---|---|---|---|
| `.claude/` | Claude | **本リポジトリの実行時設定**。settings.json / hooks / claudeos カーネル / worktrees | ❌ |
| `Claude/` | Claude | **他プロジェクト配布用テンプレ**。`Start-ClaudeOS.ps1` が source として使う | ✅ 配布される |
| `docs/claude/` | Claude | 人間向けドキュメント（概要 / 使い方 / ベストプラクティス） | ✅ リポジトリ残存 |
| `.codex/` | Codex | Codex CLI の実行時設定（shell / model / reasoning effort） | ❌ |
| `docs/codex/` | Codex | Codex CLI ドキュメント（概要 / ベストプラクティス） | ✅ |
| `.github/` | GitHub | Actions workflows / Issue templates | リポジトリ固有 |

### よくある混同ポイント

- **`.claude/` を触りたい → 本リポジトリ自体の Claude Code 動作を変更したい**
- **`Claude/` を触りたい → 他プロジェクトへ配布するテンプレを更新したい**
- **`docs/claude/` を触りたい → 利用者向けの説明を追加・修正したい**

各ディレクトリ直下に `README.md` を配置しており、目的を即座に確認できます。

## 3. 用語集

本プロジェクト固有の用語と、一般用語から意味が拡張されているものを列挙します。

| 用語 | 定義 | 関連 |
|---|---|---|
| **Agent** | 特化ロールを持つ Claude Code サブエージェント（現 17 体）。Task tool 経由で並列起動される | `.claude/agents/`, CLAUDE.md §6 |
| **Agent Teams** | 複数 Agent を Orchestrator 配下で並列運用する仕組み。単発 subagent と区別 | CLAUDE.md §6 |
| **Role** | CTO / Architect / Developer / Reviewer 等の責務単位。Agent とは直交する概念 | CLAUDE.md §6 |
| **Loop** | Monitor / Build / Verify / Improvement の 4 フェーズ自律開発サイクル | CLAUDE.md §5 |
| **Profile** | *Codex 側の概念*。旧 `.codex/config.toml` にあった `profiles.default` 等。v3.2.18 で廃止 | `.codex/config.toml` |
| **STABLE** | CI / test / lint / build / review / security / error=0 を満たし、連続 N 回成功した状態 | CLAUDE.md §9 |
| **STABLE N** | STABLE 判定に必要な連続成功回数（小規模 N=2 / 通常 N=3 / 重要 N=5） | CLAUDE.md §9 |
| **Effort** | Opus 4.7 の推論深度制御。`xhigh` / `high` / `medium` / `low` / `max` の 5 段階 | CLAUDE.md §10.5 |
| **task_budget** | Opus 4.7 beta 機能。モデル自身が残予算を見て自己ペーシングする | CLAUDE.md §13.5 |
| **`/compact`** | 会話履歴を要約して Token を開放。v8.2 で事前発動規約化 | CLAUDE.md §12 |
| **Issue Factory** | KPI 未達 / CI 失敗時に自動で Issue を生成する機構 | CLAUDE.md §7 |
| **WorkTree** | 1 Issue = 1 WorkTree の並列開発単位。main への直 push 禁止 | CLAUDE.md §10 |
| **hookify** | PreToolUse hook による CTO 委任違反などの自動検知機構 | `docs/common/17_hookify-CTO-guard.md` |

## 4. 関連ドキュメント

| 目的 | ドキュメント |
|---|---|
| まず何をするか | [`01_はじめに.md`](./01_はじめに.md) |
| Windows セットアップ | [`03_Windowsセットアップ.md`](./03_Windowsセットアップ.md) |
| CI の詳細 | [`09_CIと実機ヘルスチェック.md`](./09_CIと実機ヘルスチェック.md) |
| 自律開発の仕組み | [`11_自律開発コア.md`](./11_自律開発コア.md) |
| Agent Teams 対応表 | [`08_AgentTeams対応表.md`](./08_AgentTeams対応表.md) |
| hookify ガード | [`17_hookify-CTO-guard.md`](./17_hookify-CTO-guard.md) |
| ClaudeOS カーネル | [`../../.claude/claudeos/system/orchestrator.md`](../../.claude/claudeos/system/orchestrator.md) |
