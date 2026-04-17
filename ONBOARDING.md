# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New Onboarding

> このファイルは `/team-onboarding` により自動生成されます。
> 手動編集は次回実行時に上書きされます。恒久的な記述は `CLAUDE.md` または `docs/` に配置してください。

**生成日時**: 2026-04-14T00:00:00Z
**ClaudeOS バージョン**: v8 (Weekly Optimized Loops + CodeRabbit 統合)
**Git ブランチ**: main（生成時点。実作業は feature branch で実施）
**リポジトリ**: https://github.com/Kensan196948G/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New

---

## 1. このプロジェクトの Goal

`state.json` が未存在のため、CLAUDE.md §4 Goal Driven System のテンプレートから初期値を提示:

| 項目 | 現在値 |
|---|---|
| Goal Title | 自律開発最適化（初期値） |
| Goal Description | ClaudeOS v8 による完全無人運用の確立と Claude Code 中心の開発体験向上 |
| 運用モード | Auto Mode + Agent Teams |
| 最大作業時間 | 300 分（5 時間） |

> 実運用では初回 Monitor ループ終了時に `state.json` が生成され、以降はその内容が正となります。

## 2. 現在の KPI 状態

| KPI | 目標値 | 現在値 |
|---|---|---|
| success_rate_target | 0.9 | 未計測（state.json 未存在） |

## 3. よくハマるポイント（実履歴からの抽出）

`state.json.learning.failure_patterns` が未存在のため、抽出できません。

> 初回セッション後に自動蓄積され、次回 `/team-onboarding` 実行時に反映されます。
> 代替として、Git ログから最近の修復系コミットを参照: `fix(issue-sync)` 系が 2 件連続しており、
> Issue Sync 周りが直近のハマりどころだった可能性があります（#86, #87）。

## 4. 過去の成功パターン

`state.json.learning.success_patterns` が未存在のため、抽出できません（初回セッション後に蓄積）。

## 5. 利用可能な Agent Teams

`.claude/claudeos/agents/` 直下に **37 体** の特化サブエージェントが配置されています。

| カテゴリ | Agent |
|---|---|
| 統括・計画 | `chief-of-staff` / `orchestrator` / `planner` / `loop-operator` |
| 設計 | `architect` / `api-designer` |
| 実装（言語別 resolver） | `build-error-resolver` / `cpp-build-resolver` / `go-build-resolver` / `java-build-resolver` / `kotlin-build-resolver` / `rust-build-resolver` / `pytorch-build-resolver` |
| レビュー（言語別） | `code-reviewer` / `cpp-reviewer` / `go-reviewer` / `java-reviewer` / `kotlin-reviewer` / `python-reviewer` / `rust-reviewer` / `typescript-reviewer` / `database-reviewer` / `security-reviewer` |
| 開発（領域別） | `dev-api` / `dev-ui` |
| 品質 | `qa` / `tester` / `tdd-guide` / `e2e-runner` |
| 運用 | `ops` / `release-manager` / `incident-triager` / `security` |
| 改善・ドキュメント | `refactor-cleaner` / `doc-updater` / `docs-lookup` / `harness-optimizer` |

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
| 32ce37a | feat(claudeos): v8 Weekly Optimized Loops へアップグレード (#99) |
| e698d21 | chore(deps): bump actions/checkout from 4 to 6 (#96) |
| b4451e8 | security(ci): PSScriptAnalyzer lint ジョブを追加 (Issue #92 P1) (#98) |
| 4db3e35 | security: SECURITY.md を追加 (Issue #92 P2 対応) (#97) |
| f0db91b | chore: .gitignore に .github/CLAUDE.md と docs/CLAUDE.md を追加 (#95) |
| 095c127 | security(deps): Dependabot 設定を追加 (Issue #92) (#94) |
| 1e01bbf | security(ci): permissions ブロックを contents: read に絞る (Issue #92) (#93) |
| 3a164dd | chore: .gitignore に docs/common/CLAUDE.md を追加 (#91) |
| 2b7e049 | docs(changelog): v2.9.0 STABLE 化 + v3.0.0 Phase 4 計画追記 (#90) |
| 7fe8b59 | docs: Phase 3 完了・Phase 4 着手を README と v3ロードマップに反映 (#89) |
| 4bc39a6 | feat(templates): ClaudeOS v7.5 テンプレート更新・CodeRabbit 統合・/team-onboarding 実装 |
| eef346f | fix(issue-sync): issues イベント自動トリガーを無効化 (#87) |
| cfe98bd | fix(issue-sync): branch protection 対策 (#86) |
| 8c736c2 | chore: .gitignore に claude-mem 自動生成 CLAUDE.md を追加 (#84) |
| 214f098 | chore(claudeos): v7.4 → v7.5 — CodeRabbit 統合ポリシー追加 (#83) |
| e3f38ef | feat(dashboard): Issue #71 Dashboard に state.json KPI/フェーズ統合 (#82) |
| f8e8885 | feat(boot): Issue #70 Memory Restore を McpHealthCheck.psm1 でワイヤリング (#81) |
| 752ef4a | feat(boot): Issue #68 Agent Init を AgentTeams.psm1 でワイヤリング (#80) |
| 801264b | chore: フェーズ別モデル制御設定を追加 (#79) |
| 083b16e | chore: gitleaks workflow + Agent Teams Light mode (#77) |

## 9. 未解決の Codex 指摘

`state.json.codex.blocking_issues` が未存在のため、未解決指摘の抽出はできません。

> 直近で Codex レビューが実行されていない、または state.json がまだ生成されていない状態です。
> 次回 Verify フェーズで `/codex:review` を実行すれば、結果が state.json.codex に記録されます。

## 10. セッション開始手順

CLAUDE.md §0 のデフォルト 4 ループ登録（state.json が未存在のため標準配分を使用）:

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

`state.json.execution.phase` が未存在のため、前回セッション情報はありません。

> 通常は Monitor フェーズから開始し、GitHub Projects / Issues / CI の状態を確認して次のアクションを決定します。

---

## 付録: このファイルの生成元

- **コマンド定義**: `.claude/claudeos/commands/team-onboarding.md`
- **データソース**:
  - `./CLAUDE.md`（運用規約）
  - `./state.json`（未存在）
  - `./README.md`
  - `.claude/claudeos/agents/**/*.md`（Agent 定義）
  - `.claude/claudeos/commands/*.md`（Command 定義）
  - `git log --oneline -20`（直近コミット）

## 付録: Verify 連動自動更新

STABLE 達成時に本ファイルを自動再生成するフックは **Issue #100** として起票済みです。
実装完了後、`.claude/claudeos/hooks/hooks.json` の PostToolUse にフックが登録され、
Verify ループで STABLE が成立するたびに本ファイルが最新化されます。
