# Agent Role Mapping v1.0

_`.claude/claudeos/agents/` に実在する 37 の agent ファイルと、CLAUDE.md v7.4 で定義される 8 論理ロール（+ 拡張ロール）との正式対応表。_

---

## 背景

2026-04-11 の外部評価レポートおよび独立検証で、以下 2 つの構造矛盾が指摘された:

1. **CLAUDE.md §5.1 (役割定義表) と §5.2 (起動順序表) の不一致**
   §5.1 は 8 役割を定義するが、§5.2 の起動チェーンには `ProductManager`・`Analyst`・`EvolutionManager`・`ReleaseManager` が登場する（§5.1 には存在しない）

2. **実在 37 agents と 8 論理ロールの粒度齟齬**
   実際のファイル構成は技術別 reviewer / build-resolver が多く、8 役割とは別体系で並んでいる。`scripts/lib/AgentTeams.psm1` の `$script:CoreRoles` には **12 agents しか明示マップされていない**（25 が未分類）

本ドキュメントは両問題を同時に解決する唯一の真実源 (single source of truth) として機能する。CLAUDE.md §5.1 / §5.2 / AgentTeams.psm1 の 3 箇所は、今後この表を参照先として整合化する。

---

## 1. 論理ロール定義（9 roles + 4 extended）

### 1.1 Core Roles (9)

§5.1 の 8 役割に **Support** (docs / refactor 等の横断支援) を加えた 9 ロール構成を正とする。

| # | Role | Emoji | 責務 | 典型的な phase |
|---|---|---|---|---|
| 1 | **CTO** | 🧠 | 優先順位判断、継続可否、最終 merge 判断 | Monitor / Release |
| 2 | **Architect** | 🏗 | システム設計、API 設計、責務分離 | Development |
| 3 | **Developer** | 👨‍💻 | 実装、修正、機能追加 | Development |
| 4 | **Reviewer** | 🔎 | コード品質、保守性、言語別レビュー | Verify |
| 5 | **Debugger** | 🧰 | 原因分析、ビルド切り分け、incident triage | Repair |
| 6 | **QA** | 🧪 | テスト設計、実行、品質評価 | Verify |
| 7 | **Security** | 🔐 | 脆弱性、認証、secrets、監査 | Verify |
| 8 | **DevOps** | 🚀 | CI/CD、デプロイ、インフラ監視 | Verify / Release |
| 9 | **Support** | 📚 | docs、refactor、docs-lookup 等の横断支援 | Improvement |

### 1.2 Extended Roles (4) — 起動チェーン用論理層

§5.2 起動順序で登場する拡張ロールは、**物理 agent ファイルに対応せず、CLAUDE.md §5.2 の記述上の論理層としてのみ存在** する。本 mapping ではこれらを "logical-only" とマークし、実体 agent に委任する。

| # | Extended Role | 実体 delegation | 説明 |
|---|---|---|---|
| 10 | ProductManager | `planner` + `chief-of-staff` | Issue 生成と要件整理（planner がタスク分解、chief-of-staff が関係者調整） |
| 11 | Analyst | `loop-operator` + `orchestrator` | KPI 分析とメトリクス評価（loop-operator が状態監視、orchestrator が集約） |
| 12 | EvolutionManager | `refactor-cleaner` + `architect` | 改善提案と自己進化管理（学習 / 再設計） |
| 13 | ReleaseManager | `release-manager` | リリース管理（専用 agent あり） |

**重要**: 起動順序表に Extended Role 名を書いた場合、本表の delegation に従って実 agent を起動する。

---

## 2. 37 Agents → 9 Core Roles 完全対応表

以下は `.claude/claudeos/agents/*.md` の実ファイル 37 件すべてを、上記 9 core roles に分類したもの。

### 2.1 CTO (🧠) — 4 agents

| ID | name | 備考 |
|---|---|---|
| `loop-operator` | loop-operator | Monitor/Build/Verify/Improve ループの運用・継続可否判断 |
| `orchestrator` | orchestrator | Agent Teams 全体の協調制御 |
| `planner` | planner | 機能追加・リファクタ・移行タスクの計画分解 |
| `chief-of-staff` | chief-of-staff | 関係者間の依頼/報告/合意形成 |

### 2.2 Architect (🏗) — 2 agents

| ID | name | 備考 |
|---|---|---|
| `architect` | architect | システムアーキテクチャ整合性 |
| `api-designer` | api-designer | REST / gRPC / Webhook / エラーモデル等の API 設計 |

### 2.3 Developer (👨‍💻) — 2 agents

| ID | name | 備考 |
|---|---|---|
| `dev-api` | dev-api | Backend 実装専任 |
| `dev-ui` | dev-ui | Frontend / UI 実装専任 |

### 2.4 Reviewer (🔎) — 9 agents (言語特化多数)

| ID | name | 言語 / 領域 |
|---|---|---|
| `code-reviewer` | code-reviewer | 汎用品質・可読性・保守性 |
| `cpp-reviewer` | cpp-reviewer | C++ 所有権 / 例外安全 |
| `database-reviewer` | database-reviewer | スキーマ / インデックス / マイグレーション |
| `go-reviewer` | go-reviewer | Go idiom / 並行 / 安全性 |
| `java-reviewer` | java-reviewer | Java / Spring Boot / トランザクション |
| `kotlin-reviewer` | kotlin-reviewer | Kotlin / Android / KMP / null 安全 |
| `python-reviewer` | python-reviewer | Python 型 / 例外 / pytest 整合 |
| `rust-reviewer` | rust-reviewer | Rust 所有権 / 借用 / 非同期 |
| `typescript-reviewer` | typescript-reviewer | TypeScript / React / Next.js |

### 2.5 Debugger (🧰) — 8 agents (build-resolver 群 + incident triage)

| ID | name | 領域 |
|---|---|---|
| `build-error-resolver` | build-error-resolver | 汎用ビルド/ランタイム/依存解決 |
| `cpp-build-resolver` | cpp-build-resolver | C++ / CMake / リンカ |
| `go-build-resolver` | go-build-resolver | Go build / module / toolchain |
| `java-build-resolver` | java-build-resolver | Maven / Gradle / Spring Boot |
| `kotlin-build-resolver` | kotlin-build-resolver | Gradle / Android / KMP |
| `pytorch-build-resolver` | pytorch-build-resolver | PyTorch / CUDA / GPU メモリ |
| `rust-build-resolver` | rust-build-resolver | Rust コンパイル / trait / Cargo |
| `incident-triager` | incident-triager | 障害 / アラート / 緊急切り分け |

### 2.6 QA (🧪) — 5 agents

| ID | name | 備考 |
|---|---|---|
| `qa` | qa | 汎用品質分析・バグ検出 |
| `tdd-guide` | tdd-guide | TDD 誘導・失敗テストから段階進行 |
| `e2e-runner` | e2e-runner | Playwright E2E 設計・実行・失敗分析 |
| `tester` | tester | 自動テスト実行 |
| `harness-optimizer` | harness-optimizer | 評価ハーネス / テストハーネス最適化 |

### 2.7 Security (🔐) — 2 agents

| ID | name | 備考 |
|---|---|---|
| `security` | security | セキュリティスキャン / 脆弱性検出 |
| `security-reviewer` | security-reviewer | 脆弱性 / 認可 / 秘密情報 / 危険入力処理 |

### 2.8 DevOps (🚀) — 2 agents

| ID | name | 備考 |
|---|---|---|
| `ops` | ops | インフラ / デプロイ監視 |
| `release-manager` | release-manager | リリース判断 / 変更履歴 / rollback |

### 2.9 Support (📚) — 3 agents (横断支援)

| ID | name | 備考 |
|---|---|---|
| `doc-updater` | doc-updater | README / 設計書 / 運用文書の一貫性 |
| `docs-lookup` | docs-lookup | 既存ドキュメント / API 仕様 / 過去設計からの根拠提示 |
| `refactor-cleaner` | refactor-cleaner | 読みづらいコード / 重複 / 命名整理 |

---

## 3. Role count summary

| Role | Count | 全体比 |
|---|---|---|
| CTO | 4 | 10.8% |
| Architect | 2 | 5.4% |
| Developer | 2 | 5.4% |
| Reviewer | 9 | 24.3% |
| Debugger | 8 | 21.6% |
| QA | 5 | 13.5% |
| Security | 2 | 5.4% |
| DevOps | 2 | 5.4% |
| Support | 3 | 8.1% |
| **合計** | **37** | **100%** |

**観測**: Reviewer (24.3%) と Debugger (21.6%) の合計が 45.9% を占める。これは言語ごとに reviewer / build-resolver を用意する設計思想の直接的結果であり、「レビューとビルド解決の専門分化」がこのプロジェクトの基本方針であることを示している。

---

## 4. 起動チェーンの補正版 (Monitor chain 例)

CLAUDE.md §5.2 の起動順 `CTO → ProductManager → Analyst → Architect → DevOps` を、本 mapping で補正すると:

```
CTO                                 → loop-operator, planner (or orchestrator)
ProductManager (logical)            → planner (タスク分解), chief-of-staff (調整)
Analyst (logical)                   → loop-operator (状態監視), orchestrator (集約)
Architect                           → architect, api-designer
DevOps                              → ops, release-manager
```

実際の Monitor phase では、light mode なら CTO + Architect + DevOps の **6 agents** で十分。full mode では 10 agents を並行起動する。

---

## 5. Classification ⊥ Activation — 2 次元モデル

本 mapping 策定の過程で、`scripts/lib/AgentTeams.psm1` の既存設計を精読した結果、
**「分類 (classification)」と「発動 (activation)」は独立した直交軸** であることが判明した。
この区別は本 mapping の読み方を左右するため、本節で明示的に定義する。

### 5.1 二軸の定義

| 軸 | 質問 | 担当 |
|---|---|---|
| **Classification** | この agent は何を専門とするのか？ | 本 `agent-role-mapping.md` が決定する |
| **Activation** | いつこの agent が team に参加するのか？ | `AgentTeams.psm1` の runtime ロジックが決定する |

### 5.2 Activation の 2 種類

`AgentTeams.psm1 New-AgentTeam` は team を 2 つの集合に分割する:

| 集合 | 発動条件 | 実装箇所 |
|---|---|---|
| **coreTeam (always-on)** | `$script:CoreRoles` に列挙された agent は常に参加 | `AgentTeams.psm1:188-202` |
| **specialists (task-driven)** | `Get-TaskTypeAnalysis` が task description にマッチした場合のみ参加 | `AgentTeams.psm1:204-219` |

### 5.3 なぜ Developer 役が「空」で Reviewer が code-reviewer のみなのか

現状 `$script:CoreRoles` の一見「不完全」な内容は、実は意図的な設計である:

```powershell
[pscustomobject]@{ role = 'Developer'; emoji = '👨‍💻'; agents = @() }
[pscustomobject]@{ role = 'Reviewer';  emoji = '🔎'; agents = @('code-reviewer') }
```

**理由**: 技術別の dev / reviewer / build-resolver は **specialists** として、task 内容（API / UI / C++ / Rust / Django 等）に応じて動的に召集される設計。`tests/AgentTeams.Tests.ps1:242-245` の「`dev-api が specialist に含まれること`」という assert がこれを直接実証している。

もし本 mapping 上の classification をそのまま `$script:CoreRoles` に転写すると、以下が起きる:

1. すべての language reviewer が always-on となり、どんな task でも 9 人の reviewer が並列起動する → 無駄
2. `specialists` が常に空となり、task-type による動的チーム編成が機能しなくなる
3. `dev-api が specialist に含まれること` テストが失敗する

### 5.4 正しい同期方針

| アプローチ | 判定 | 備考 |
|---|---|---|
| **A: CoreRoles に全 37 を詰め込む** | ❌ 却下 | 5.3 の問題で specialists が死ぬ |
| **B: mapping doc を 2 層化し psm1 は現状維持** | ✅ 採用 | 本節がこれ |
| **C: psm1 に小幅追加（CTO + chief-of-staff 等の本当の always-on のみ）** | 🟡 今後検討 | 別 PR で必要性評価 |

### 5.5 Classification / Activation の対応表

§2 で定義した 9 Core Roles は **Classification 軸** 専用。Activation 軸との対応は以下:

| Classification (本 doc) | 既定の Activation (psm1) | 備考 |
|---|---|---|
| CTO (4 agents) | coreTeam (2 agents: loop-operator, planner) | 残 2 (orchestrator, chief-of-staff) は現状 activation 非対象 |
| Architect (2) | coreTeam (2: architect, api-designer) | 完全一致 |
| Developer (2) | specialists (dev-api, dev-ui は task-type "api" / "ui" で発動) | 空 coreTeam は意図的 |
| Reviewer (9) | coreTeam (1: code-reviewer), specialists (8 language reviewers) | code-reviewer は汎用 always-on |
| Debugger (8) | specialists のみ (build-resolvers は task-type "ci" / "build" で発動) | psm1 に Debugger role は未定義だが実質機能している |
| QA (5) | coreTeam (3: qa, tdd-guide, e2e-runner), specialists (tester, harness-optimizer) | 混在 |
| Security (2) | coreTeam (2) | 完全一致 |
| DevOps (2) | coreTeam (2: ops, release-manager) | 完全一致 |
| Support (3) | 現状どちらでもない (future work) | Improvement phase で活用予定 |

### 5.6 psm1 sync の scope 再定義

本 mapping 採択後の `AgentTeams.psm1` への修正は、以下 **小幅** に限定する:

1. `$script:CoreRoles` への `Debugger` role 追加（agents: `incident-triager` のみ。build-resolvers は specialists に留める）
2. CTO role への `orchestrator` / `chief-of-staff` 追加検討（要 A/B 評価）
3. `QA` role への `tester` 追加検討（要 A/B 評価）

上記はいずれも **本 session スコープ外** とし、別 PR で慎重に評価する。**既存の specialist ロジックと既存テストを壊さない** ことを最優先とする。

---

## 6. 更新プロトコル

新しい agent を `.claude/claudeos/agents/` に追加した場合、**必ず** 以下を同時に実施する:

1. 本 mapping の §2 に新行を追加
2. §3 の role count を更新
3. `AgentTeams.psm1` の `$script:CoreRoles` にも追加（§5 同期）
4. CLAUDE.md §5.1 の 9 roles と齟齬がないか確認

agent ファイルを削除した場合も同様に 3 箇所を同期する。

---

## 7. 検証方法

本 mapping が実態と一致していることを自動検証するには:

```powershell
# scripts/eval/verify-agent-mapping.ps1 (未作成)
Import-Module ./scripts/lib/AgentTeams.psm1 -Force -DisableNameChecking
$agents = Import-AgentDefinitions -AgentsDir '.claude/claudeos/agents'
# mapping ファイル parse と照合
```

fact-check.ps1 の拡張で「各 agent id が mapping 表に必ず出現すること」を検証することも可能（本 mapping 側の claim list に全 37 id を登録）。

---

## 8. Revision History

| version | date | author | change |
|---|---|---|---|
| v1.0 | 2026-04-11 | Claude Opus 4.6 (CTO delegation) | 初版。Evaluation Sign-Flip Incident の構造矛盾 #8 を解決 |

---

## 9. 関連ドキュメント

- `.claude/claudeos/system/evaluation-methodology.md` — 本 mapping が解消した「役割表不一致 (§5.1 vs §5.2)」の元指摘
- `.claude/claudeos/system/role-contracts.md` — light/full mode 設計
- `scripts/lib/AgentTeams.psm1` — 本 mapping を反映すべき runtime 側
- `CLAUDE.md §5` — 本 mapping の参照先となる規約節
