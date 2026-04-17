# ClaudeCode-StartUpTools-New Onboarding

> このファイルは `/team-onboarding` により自動生成されます。
> 手動編集は次回実行時に上書きされます。恒久的な記述は `CLAUDE.md` または `docs/` に配置してください。

**生成日時**: 2026-04-17T21:30:00+09:00
**ClaudeOS バージョン**: v8 (Weekly Optimized Loops + CodeRabbit 統合 + 3タブ監視)
**Git ブランチ**: main（生成時点。実作業は feature branch で実施）
**リポジトリ**: https://github.com/Kensan196948G/ClaudeCode-StartUpTools-New

---

## 1. このプロジェクトの Goal

`state.json` から取得した現在値:

| 項目 | 現在値 |
|---|---|
| Goal Title | ClaudeOS v8 自律開発最適化 |
| Goal Description | ClaudeOS v8 による完全無人運用の確立と Claude Code 中心の開発体験向上 |
| 運用モード | Auto Mode + Agent Teams |
| 最大作業時間 | 300 分（5 時間） |
| 現在フェーズ | Monitor |

## 2. 現在の KPI 状態

| KPI | 目標値 | 現在値 |
|---|---|---|
| success_rate_target | 0.9 | 0.9（state.json より） |

## 3. よくハマるポイント（実履歴からの抽出）

`state.json.learning.failure_patterns` は現セッションでは未記録（セッション進行で自動蓄積）。

Git ログから直近の修復系コミット（fix/hotfix 系）を参照:

| 傾向 | 詳細 |
|---|---|
| CodeRabbit Critical 指摘 | injection 系 / SSH コマンド構築 — v3.2.19 で解消 |
| SSH 診断性向上 | ssh_error 吸収 + SSH エラーメッセージの可観測性 |
| PSScriptAnalyzer 警告蓄積 | PSProvideCommentHelp / PSUseOutputTypeCorrectly など段階的解消中 |

## 4. 過去の成功パターン

`state.json.learning.success_patterns` は現セッションでは未記録。
直近 STABLE 達成実績: N=2 連続（v3.2.6 / v3.2.19）。

## 5. 利用可能な Agent Teams

`.claude/claudeos/agents/` 直下に **25 体** の特化サブエージェントが配置されています。

| カテゴリ | Agent |
|---|---|
| 統括 | `orchestrator` |
| 設計 | `architect` |
| 実装（言語別 resolver） | `build-error-resolver` / `cpp-build-resolver` / `go-build-resolver` / `java-build-resolver` / `kotlin-build-resolver` / `rust-build-resolver` / `pytorch-build-resolver` |
| レビュー（言語別） | `cpp-reviewer` / `go-reviewer` / `java-reviewer` / `kotlin-reviewer` / `python-reviewer` / `rust-reviewer` / `typescript-reviewer` / `database-reviewer` / `security-reviewer` |
| 開発（領域別） | `dev-api` / `dev-ui` |
| 品質 | `qa` / `tester` / `e2e-runner` |
| 運用 | `ops` / `security` |

> 各 Agent の詳細な description は、該当 Agent を呼び出した際にロードされるフロントマターから取得してください。
> CLAUDE.md §6 に Agent Teams のロール対応表があります。

## 6. 利用可能なスラッシュコマンド

`.claude/claudeos/commands/` 直下に **34 個** のコマンドが配置されています。

| カテゴリ | Command |
|---|---|
| オンボーディング | `/team-onboarding` |
| 計画・オーケストレーション | `/plan` / `/orchestrate` / `/multi-plan` / `/multi-workflow` / `/multi-execute` |
| レビュー | `/code-review` / `/go-review` / `/python-review` |
| ビルド・テスト | `/build-fix` / `/go-build` / `/go-test` / `/verify` / `/test-coverage` |
| マルチスタック | `/multi-backend` / `/multi-frontend` |
| TDD・E2E | `/tdd` / `/e2e` |
| セッション管理 | `/checkpoint` / `/sessions` / `/prune` |
| 学習・進化 | `/learn` / `/learn-eval` / `/evolve` / `/eval` |
| Instinct（直感記録） | `/instinct-export` / `/instinct-import` / `/instinct-status` |
| ドキュメント | `/update-docs` / `/update-codemaps` |
| 改善 | `/refactor-clean` |
| プロジェクト管理 | `/pm2` / `/setup-pm` |
| スキル作成 | `/skill-create` |

## 7. 禁止事項（CLAUDE.md §18 の全項目を動的ミラー）

CLAUDE.md §18 から抽出した **全 8 項目**:

1. Issue なし作業
2. main 直接 push
3. CI 未通過 merge
4. 無限修復（Auto Repair 制御に従う）
5. 未検証 merge
6. 原因不明修正
7. Token 超過のまま深掘り継続
8. 時間不足時の大規模変更

> この一覧は CLAUDE.md §18 の動的ミラーです。§18 を更新すれば次回 `/team-onboarding` 実行時に自動追従します。

## 8. 直近の Git 活動

直近 20 コミット:

| Hash | 概要 |
|---|---|
| 90ec63d | chore(v3.2.19): ClaudeOS config 整理 — CLAUDE.md v8.2→v8, token-budget 簡略化 |
| 22ddc2e | fix(v3.2.19): CodeRabbit Round 2 指摘 — Critical injection + Major ssh_error 吸収 |
| 17758b1 | fix(v3.2.19): CodeRabbit + Copilot レビュー 4 件対応 — SSH 診断性向上 |
| 47ef4e0 | feat(v3.2.19): 3 タブ監視 品質向上 (外部レビュー追加指摘 3 件) |
| 9d7bc83 | chore: TASKS.md — v3.2.18 [DONE] 更新 + v3.2.19 起票 (PR #169) |
| 26e8b22 | feat(v3.2.18): 外部コードレビュー指摘 5 カテゴリ対応 (Quick-wins) (#169) |
| 25ae708 | feat(v3.2.17): 3タブ監視構成 + tmux UI 統合 + linuxUser パラメータ化 (#168) |
| e31a547 | chore: TASKS.md — v3.2.14 [DONE] 更新 (PR #167) |
| 6819125 | docs(v3.2.14): PSProvideCommentHelp 警告 85 件解消 — 9 ファイル全関数に追加 (#167) |
| 37e213b | chore: TASKS.md — v3.2.13 [DONE] 更新 (PR #165) |
| 20c3972 | fix: PSAvoidUsingPositionalParameters 残存 1 件解消 (#165) |
| 8353a23 | docs(v8.3): CLAUDE.md に Auto mode 操作手順を追加 |
| 5e03081 | feat(v3.2.12): PSUseOutputTypeCorrectly 警告 37 件解消 (#164) |
| 007934d | chore: TASKS.md — v3.2.11 [DONE] 更新 (PR #163) |
| 3b8a0a8 | feat(v3.2.11): PSAvoidUsingPositionalParameters 警告解消 (#163) |
| 08ce0fe | feat(v3.2.10): PSReviewUnusedParameter 警告 7 件解消 (#162) |
| e562c00 | docs(v3.2.9): TASKS.md + CHANGELOG 更新 |
| 57cf203 | feat(v3.2.9): PSUseShouldProcessForStateChangingFunctions 警告 26 件解消 (#160) |
| 9ede059 | feat(v8.3): Anthropic 公式ブログ Opus 4.7 best-practices を CLAUDE.md に反映 |
| ee6235d | docs(v3.2.8): TASKS.md task 25 を DONE に更新 |

## 9. 未解決の Codex 指摘

`state.json.codex` ブロックは現セッション未実行のため空。

> 次回 Verify フェーズで `/codex:review --base main` を実行すれば、結果が state.json.codex に記録されます。

## 10. セッション開始手順

CLAUDE.md §0 のデフォルト 4 ループ登録（state.json.execution.phase=Monitor から継続）:

```text
/loop 30min   ClaudeOS Monitor
/loop 2h      ClaudeOS Development
/loop 1h15m   ClaudeOS Verify
/loop 1h15m   ClaudeOS Improvement
```

配分内訳: Monitor 10% / Development 40% / Verify 25% / Improvement 25%（計 5 時間）。

続いて Codex セットアップ:

```text
/codex:setup
/codex:status
```

リリース直前のみ: `/codex:setup --enable-review-gate`

## 11. 再開ポイント（前回セッション未完了時）

`state.json.execution` より:

| 項目 | 値 |
|---|---|
| 前回停止 | 2026-04-17T13:00:12Z |
| 前回要約 | v3.2.6 (PR #154) を main へ admin squash merge 完了。PSUseApprovedVerbs 警告 9 件解消。STABLE N=2 達成。 |
| 現在フェーズ | Monitor |

現在ブランチ `feature/v3.2.19-tab-monitoring-quality` で作業継続中。Monitor フェーズから再開し、GitHub Projects / Issues / CI の状態を確認して次のアクションを決定してください。

---

## 付録: このファイルの生成元

- **コマンド定義**: `.claude/claudeos/commands/team-onboarding.md`
- **データソース**:
  - `./CLAUDE.md`（運用規約）
  - `./state.json`（存在 — goal/kpi/execution/frontier 等記録済み）
  - `./README.md`
  - `.claude/claudeos/agents/**/*.md`（Agent 定義）
  - `.claude/claudeos/commands/*.md`（Command 定義）
  - `git log --oneline -20`（直近コミット）

## 付録: Verify 連動自動更新

STABLE 達成時に本ファイルを自動再生成するフックは **Issue #100** として起票済みです。
実装完了後、`.claude/claudeos/hooks/hooks.json` の PostToolUse にフックが登録され、
Verify ループで STABLE が成立するたびに本ファイルが最新化されます。
