# Agent Teams 対応表

このドキュメントは、[Claude/claudeos](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/Claude/claudeos/) にある ClaudeOS ポリシーと、現行ランチャー実装およびツール別テンプレートの対応関係を整理するためのものです。

ツール別の可能 / 擬似実装 / 不可 は [12_自律機能対応表.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/docs/common/12_自律機能対応表.md) を参照してください。

## 対応状況

対応レベル:
- `0`: 未対応
- `1`: 代替のみ
- `2`: 部分対応
- `3`: 実運用可能だが不足あり
- `4`: ほぼ対応
- `5`: フル対応

算定基準:
- `0`: 実装も代替もない。
- `1`: 実ランタイムは無いが、手動運用や表示で代替している。
- `2`: 設定読込、診断、補助機能の一部だけ実装済み。
- `3`: 日常運用で使えるが、自動化や統合が不足している。
- `4`: コア要件の大半を満たし、残件は周辺機能のみ。
- `5`: ClaudeOS ポリシーの期待を実運用レベルで満たしている。

| ClaudeOS 要素 | 現行実装 | 状態 | 対応レベル |
|---|---|---|---|
| Orchestrator | 起動フローの中心は `start.bat` / `Start-Menu.ps1` / `Start-All.ps1` | 部分対応 | 3 |
| Project Switch | `Start-*.ps1` のプロジェクト選択、`recentProjects` 記録、成功可否ソート | 部分対応 | 3 |
| Monitor Loop | `scripts/test/Test-AllTools.ps1`、`test-drive-mapping.ps1` | 部分対応 | 3 |
| Verify Loop | `Invoke-Pester .\tests`、GitHub Actions CI | 部分対応 | 3 |
| CI Manager | `.github/workflows/ci.yml` | 部分対応 | 3 |
| Agent Teams 会話可視化 | `AgentTeams.psm1` でランタイムTeam構成・可視化。37 Agent定義読込、17パターン自動割当 | 実運用可能 | 3 |
| MCP サーバー連携 | `McpHealthCheck.psm1` でモジュール化。Start-Menu統合、Text/JSON出力、ヘルスチェック実行 | ほぼ対応 | 4 |
| Worktree Manager | `git worktree` 運用手順を docs 化 + ClaudeOS v8.2 §10 WorkTree 規約で並列開発を実運用 | 実運用可能 | 3 |
| Backlog Manager | `TASKS.md` と CI の同期確認 + GitHub Issue 自動生成 (PR #38) | ほぼ対応 | 4 |

## 実装済み機能

- ツール別起動: Claude Code / Codex CLI / GitHub Copilot CLI
- ローカル起動 / SSH 起動
- 設定テンプレートとスキーマ検証
- 診断スクリプトのテキスト / JSON 出力
- recent projects 記録と `Start-Menu.ps1` からの再利用
- CI による Pester 実行と設定検証
- 共通コア文書とツール別テンプレートの分離
- Claude 用 Agent Teams、Codex 用 manager-worker、Copilot 用 custom agents + fleet という翻訳方針
- MCP ヘルスチェックモジュール (`McpHealthCheck.psm1`) と Start-Menu 統合
- Agent Teams ランタイムエンジン (`AgentTeams.psm1`): 37 Agent 定義読込、17 パターン自動分類、Team 構成生成
- multi-agent 自動割当: backlog-rules.json 連携による優先度・オーナー自動判定

## 未実装機能

- Memory MCP 退避機能 (PreCompact hook 拡張、ClaudeOS v8.3 予定)
- Verify 連動 ONBOARDING.md 自動再生成フック (Issue #100)

(旧項目「worktree ベース並列ブランチ運用」「issue / backlog 自動生成」は PR #37 / PR #38 / ClaudeOS v8.2 §10 で実運用化済み)

## 自動抽出

`scripts/tools/Sync-AgentTeamsBacklog.ps1` は、この `## 未実装機能` セクションの箇条書きを読み取り、`TASKS.md` の自動抽出セクションと同期します。
抽出単位は 1 行 1 項目です。文言を変えると backlog の同期結果も変わります。
metadata の自動付与は [config/agent-teams-backlog-rules.json](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/config/agent-teams-backlog-rules.json) を参照します。端末ごとに調整したい場合は template ではなく実ファイル側を編集します。

## 今後の実装候補

1. Agent Teams 用の実行ダッシュボードを `scripts/main` に追加する
2. MCP 接続状態を JSON 診断に含める
3. ClaudeOS の loop / agent role と launch scripts の対応をコード内コメントで明示する
4. recent projects に tool / mode 情報も保存し、再起動時に再現できるようにする

## Backlog

未実装項目の優先バックログは [TASKS.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/TASKS.md) で管理します。
