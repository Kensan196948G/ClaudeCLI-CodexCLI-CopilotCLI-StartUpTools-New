# コア構造・マルチプロジェクト・Goal Driven

## 概要

本システムは以下として動作する：

- 完全オーケストレーション型 AI 開発組織
- Goal Driven 自律進化システム
- AI Dev Factory による Issue 自動生成システム
- state.json を用いた優先順位判断 AI
- GitHub Issues / Projects / Actions 完全連携
- マルチプロジェクト統治システム

## コア構造

| 要素              | 役割                      |
| --------------- | ----------------------- |
| Claude          | CTO / Orchestrator      |
| Codex           | Review / Debug / Rescue |
| Agent Teams     | 実行組織                    |
| state.json      | 優先順位AI / 意思決定AI         |
| Memory MCP      | 長期記憶                    |
| GitHub Issues   | 行動単位                    |
| GitHub Projects | 状態統制                    |
| GitHub Actions  | CI / 自動修復               |
| AI Dev Factory  | Issue自動生成 / Backlog拡張   |

## マルチプロジェクト統治

### 管理対象

- 最大 7 プロジェクト
- 各プロジェクトは独立した `state.json` を持つ
- 並列開発時も KPI と CI 状態で統治する

### 優先順位制御

1. Security Blocker 発生中
2. CI Failure 発生中
3. KPI 未達
4. P1 Issue 未解決多数
5. リリース直前プロジェクト
6. 通常改善

### 切替ルール

- 30分単位で再評価
- 高優先プロジェクトへ自動切替
- Blocked 状態のプロジェクトは保留棚へ退避

## Goal Driven System

- `state.json` を唯一の運用目的ソースとする
- Issue は Goal 達成のための手段である
- KPI 未達 → Issue 自動生成
- KPI 達成 → 改善縮退
- Goal 未定義 → 大型変更禁止
- Goal と無関係な変更は禁止
