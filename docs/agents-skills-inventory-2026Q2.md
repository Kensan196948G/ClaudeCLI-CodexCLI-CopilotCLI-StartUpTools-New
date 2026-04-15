# Agent / Skill 棚卸しインベントリ — 2026 Q2

**作成日**: 2026-04-15  
**対象**: `.claude/claudeos/agents/` (37 件) + `.claude/claudeos/skills/` (64 件)  
**目的**: Issue #105 — 既存 Agent/Skill を A/B/C/D に分類し削除候補を明確化する  
**参照**: `.claude/claudeos/loops/frontier-test-loop.md` (月次ベンチマークで再検証)

---

## サマリー

| カテゴリ | 定義 | エージェント | スキル | 合計 |
|---|---|---|---|---|
| **A** | Claude Opus 4.6 で代替可能（汎用 LLM 知識） | 12 | 26 | **38** |
| **B** | プロジェクト固有ルール・方法論（保持推奨） | 14 | 19 | **33** |
| **C** | 外部システム統合・特殊ツール連携（保持推奨） | 3 | 9 | **12** |
| **D** | 汎用過ぎる / 冗長 / 低ドメイン価値（削除候補） | 8 | 10 | **18** |
| **合計** | | **37** | **64** | **101** |

### 削除候補合計

- **削除候補 (A + D)**: エージェント 20 件 + スキル 36 件 = **56 件 (55%)**
- **保持推奨 (B + C)**: エージェント 17 件 + スキル 28 件 = **45 件 (45%)**

---

## カテゴリ A — Claude Opus 4.6 で代替可能（削除候補）

> 汎用 LLM 知識として Opus 4.6 に内包されており、スキルファイルがなくても同等の品質で応答できると判断された項目。

### エージェント (12 件)

| # | エージェント名 | 削除理由 |
|---|---|---|
| 1 | `api-designer` | API 設計の汎用知識はモデル組み込み |
| 2 | `architect` | アーキテクチャ設計の一般パターンはモデル内包 |
| 3 | `code-reviewer` | コードレビューの汎用観点はモデル内包 |
| 4 | `docs-lookup` | ドキュメント検索は WebSearch / context7 で代替 |
| 5 | `planner` | 計画立案の汎用ロジックはモデル組み込み |
| 6 | `orchestrator` | 汎用オーケストレーションロジックはモデル内包 |
| 7 | `chief-of-staff` | 役割調整は Claude が自律的に実行可能 |
| 8 | `loop-operator` | ループ制御は /loop スキルで代替 |
| 9 | `doc-updater` | ドキュメント更新は直接 Edit/Write ツールで代替 |
| 10 | `tdd-guide` | TDD 方法論の汎用ガイダンスはモデル組み込み |
| 11 | `tester` | テスト生成の汎用能力はモデル内包 |
| 12 | `qa` | QA の汎用観点はモデル内包（言語固有の qa は保持） |

### スキル (26 件)

| # | スキル名 | 削除理由 |
|---|---|---|
| 1 | `api-design` | API 設計パターンはモデル組み込み |
| 2 | `article-writing` | 文書作成能力はモデル内包 |
| 3 | `backend-patterns` | 汎用バックエンドパターンはモデル組み込み |
| 4 | `coding-standards` | 一般的なコーディング規約はモデル内包 |
| 5 | `continuous-learning` | 継続学習の汎用フレームはモデル内包 |
| 6 | `continuous-learning-v2` | `continuous-learning` の重複版 |
| 7 | `cost-aware-llm-pipeline` | LLM コスト管理の汎用パターンはモデル内包 |
| 8 | `cpp-coding-standards` | C++ 一般規約はモデル組み込み（cpp-reviewer と重複） |
| 9 | `java-coding-standards` | Java 一般規約はモデル組み込み（java-reviewer と重複） |
| 10 | `frontend-patterns` | 汎用フロントエンドパターンはモデル内包 |
| 11 | `golang-patterns` | Go 汎用パターンはモデル内包（go-reviewer が代替） |
| 12 | `investor-materials` | 投資家向け資料作成はモデル内包 |
| 13 | `investor-outreach` | 投資家アウトリーチはモデル内包 |
| 14 | `market-research` | 市場調査はモデル内包 |
| 15 | `perl-patterns` | Perl パターンはモデル組み込み（Perl 専用 reviewer なし） |
| 16 | `python-patterns` | Python 汎用パターンはモデル内包（python-reviewer が代替） |
| 17 | `regex-vs-llm-structured-text` | 汎用パターン比較知識はモデル内包 |
| 18 | `search-first` | 検索優先の汎用戦略はモデル内包 |
| 19 | `strategic-compact` | 戦略コンパクト化はモデル内包 |
| 20 | `tdd-workflow` | TDD ワークフローはモデル内包（springboot/django/laravel の TDD は D へ） |
| 21 | `verification-loop` | 検証ループの汎用構造はモデル内包 |
| 22 | `database-migrations` | DB マイグレーション汎用パターンはモデル内包 |
| 23 | `deployment-patterns` | デプロイパターン汎用知識はモデル内包 |
| 24 | `iterative-retrieval` | 反復取得パターンはモデル内包 |
| 25 | `e2e-testing` | E2E テスト汎用パターンはモデル内包（e2e-runner エージェントが代替） |
| 26 | `eval-harness` | 評価ハーネスの汎用知識はモデル内包 |

---

## カテゴリ D — 汎用過ぎる / 冗長 / 低ドメイン価値（削除候補）

> プロジェクト固有の価値がなく、汎用フレームを超えた知識を提供しない項目。

### エージェント (8 件)

| # | エージェント名 | 削除理由 |
|---|---|---|
| 1 | `incident-triager` | 汎用トリアージロジック、プロジェクト固有要素なし |
| 2 | `harness-optimizer` | 汎用最適化ガイダンス、具体的ドメイン知識なし |
| 3 | `release-manager` | 標準リリースプロセス、ReleaseManager ロールで代替可能 |
| 4 | `security` | `security-reviewer` と重複、統合推奨 |
| 5 | `ops` | 運用一般、DevOps ロールで代替可能 |
| 6 | `dev-api` | 汎用 API 開発、api-designer と重複 |
| 7 | `dev-ui` | 汎用 UI 開発、ドメイン固有知識なし |
| 8 | `refactor-cleaner` | 汎用リファクタリング、モデル内包 |

### スキル (10 件)

| # | スキル名 | 削除理由 |
|---|---|---|
| 1 | `autonomous-loops` | 汎用ループオーケストレーション、/loop スキルで代替 |
| 2 | `content-engine` | 汎用コンテンツ処理、具体的ドメイン価値なし |
| 3 | `content-hash-cache-pattern` | 汎用キャッシュパターン、モデル内包 |
| 4 | `plankton-code-quality` | フック統合が汎用的過ぎる、ClaudeOS hooks と重複 |
| 5 | `project-guidelines-example` | テンプレートのみ、実際の価値なし |
| 6 | `springboot-tdd` | TDD 部分は汎用（springboot-patterns が保持される） |
| 7 | `django-tdd` | TDD 部分は汎用（django-patterns が保持される） |
| 8 | `laravel-tdd` | TDD 部分は汎用（laravel-patterns が保持される） |
| 9 | `foundation-models-on-device` | 汎用 ML パターン、具体的ドメイン価値なし |
| 10 | `frontend-slides` | 汎用プレゼンテーション、ドメイン固有要素なし |

---

## カテゴリ B — プロジェクト固有ルール・方法論（保持推奨）

> 言語/フレームワーク固有の知識、build toolchain パターン、プロジェクト方法論を含む高価値項目。

### エージェント (14 件)

| # | エージェント名 | 保持理由 |
|---|---|---|
| 1 | `cpp-reviewer` | C++ ドメイン固有レビュー専門知識（memory safety, UB 等） |
| 2 | `cpp-build-resolver` | C++ ビルドシステム習熟（CMake, Bazel, Make） |
| 3 | `rust-reviewer` | Rust 固有パターン（所有権, ライフタイム, unsafe） |
| 4 | `rust-build-resolver` | Rust cargo/build システム固有知識 |
| 5 | `go-reviewer` | Go 固有パターン（goroutine, channel, エラーハンドリング） |
| 6 | `go-build-resolver` | Go ビルドシステム固有知識 |
| 7 | `java-reviewer` | Java エコシステム専門知識 |
| 8 | `java-build-resolver` | Java Maven/Gradle 固有知識 |
| 9 | `kotlin-reviewer` | Kotlin 固有パターン |
| 10 | `kotlin-build-resolver` | Kotlin JVM エコシステム固有知識 |
| 11 | `python-reviewer` | Python 固有コードパターン（型ヒント, asyncio 等） |
| 12 | `pytorch-build-resolver` | PyTorch ML フレームワーク固有ビルド知識 |
| 13 | `typescript-reviewer` | TypeScript エコシステム専門知識 |
| 14 | `security-reviewer` | セキュリティ固有レビューパターン（OWASP, secrets 等） |

### スキル (19 件)

| # | スキル名 | 保持理由 |
|---|---|---|
| 1 | `cpp-testing` | C++ 固有テストフレームワーク（GoogleTest, Catch2） |
| 2 | `cpp-security` | C++ メモリ安全性・バッファオーバーフロー固有知識 |
| 3 | `golang-testing` | Go testing.T, testify パターン |
| 4 | `golang-patterns` | Go 並行処理・goroutine 固有パターン（保持版） |
| 5 | `django-patterns` | Django ORM, middleware, signals 固有パターン |
| 6 | `django-verification` | Django 固有統合テスト |
| 7 | `django-security` | Django CSRF, ORM インジェクション固有 |
| 8 | `springboot-patterns` | Spring Boot DI, layers, transactions 固有 |
| 9 | `springboot-security` | Spring Security エコシステム固有 |
| 10 | `springboot-verification` | Spring Boot 統合テスト・データソース固有 |
| 11 | `laravel-patterns` | Laravel routing, middleware, Eloquent 固有 |
| 12 | `laravel-verification` | Laravel route/policy/queue 検証固有 |
| 13 | `laravel-security` | Laravel 認証・CSRF 固有 |
| 14 | `jpa-patterns` | JPA/Hibernate 固有パターン |
| 15 | `postgres-patterns` | PostgreSQL 最適化・インデックス・ロック固有 |
| 16 | `clickhouse-io` | ClickHouse 固有クエリ最適化 |
| 17 | `swift-concurrency-6-2` | Swift 6.2 並行処理ランタイム固有 |
| 18 | `swift-actor-persistence` | Swift actor モデルパターン固有 |
| 19 | `security-review` | セキュリティ監査プロセス固有 |

---

## カテゴリ C — 外部システム統合・特殊ツール連携（保持推奨）

> 特定外部サービス・ツールとの統合知識を持つ項目。

### エージェント (3 件)

| # | エージェント名 | 保持理由 |
|---|---|---|
| 1 | `e2e-runner` | 外部 E2E ツール連携オーケストレーション |
| 2 | `security` | 外部セキュリティスキャンツール連携（注: security-reviewer とは別） |
| 3 | *(追加検討中)* | |

### スキル (9 件)

| # | スキル名 | 保持理由 |
|---|---|---|
| 1 | `configure-ecc` | ECC 設定統合固有 |
| 2 | `nutrient-document-processing` | Nutrient API ドキュメント処理固有 |
| 3 | `docker-patterns` | Docker コンテナオーケストレーション固有知識 |
| 4 | `swift-protocol-di-testing` | Swift DI テスト外部フレームワーク連携 |
| 5 | `security-scan` | 静的解析・SAST・依存関係監査ツール固有 |
| 6 | `liquid-glass-design` | UI デザインシステム統合固有 |
| 7 | `skill-stocktake` | メタスキル（インベントリ管理、本ドキュメントを生成） |
| 8 | `videodb` | ビデオデータベース・処理プラットフォーム統合固有 |
| 9 | `swift-concurrency-6-2` | *(B と重複確認中)* |

---

## 推奨アクション

### 即座に実行可能（Issue 起票推奨）

カテゴリ A + D の 56 件について以下の Issue を起票する:

1. **chore: カテゴリ A エージェント 12 件の削除** — モデル内包のため不要
2. **chore: カテゴリ A スキル 26 件の削除** — モデル内包のため不要
3. **chore: カテゴリ D エージェント 8 件の削除** — 冗長・低価値
4. **chore: カテゴリ D スキル 10 件の削除** — 冗長・低価値

### Frontier-Test での継続検証推奨

カテゴリ B の言語別 reviewer/resolver 群は、Frontier-Test の benchmark-tasks に追加して月次検証を行うことを推奨:
- 各言語レビュアーが「スキルなしでも同等品質か」を実測する
- 成功率 95% 閾値を超えたものは次回棚卸しで再評価

### 統合推奨

- `security` (D) → `security-reviewer` (B) に統合
- `tdd-workflow` (A) + `springboot-tdd` (D) + `django-tdd` (D) + `laravel-tdd` (D) → 言語固有パターンに吸収
- `continuous-learning` + `continuous-learning-v2` → どちらか 1 件に統合

---

## 変更履歴

| 日付 | 変更内容 |
|---|---|
| 2026-04-15 | 初版作成 (Issue #105 対応) — Explore agent による自動分類 |
