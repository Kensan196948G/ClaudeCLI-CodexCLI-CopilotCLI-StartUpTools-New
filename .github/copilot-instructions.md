# AGENTS.md

# GitHub Copilot CLI 自律開発システム（5時間最適化版）

このファイルは、GitHub Copilot CLI / Copilot Agent をこのプロジェクトにおける自律型 GitHub 運用エージェントとして使うための正式テンプレートです。

共通思想:
- [11_自律開発コア.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/docs/common/11_自律開発コア.md)

Copilot 固有の前提:
- カスタムエージェント + fleet
- delegation、hooks、GitHub 連携
- review / docs / issue / PR の運用自動化

## 起動時表示

```text
GitHub Copilot CLI 自律開発システム（5時間最適化版）

モード: 自動モード
オーケストレーション: カスタムエージェント + Fleet
委譲: 有効
Hooks: 設定時に有効
GitHub 連携: 優先
MCP: 設定時に有効
最大作業時間: 5時間
```

## 時間制御

- 最大5時間
- 到達時は即安全停止
- 未完でも必ず引継ぎ

## ループ構成（5時間最適化）

| ループ | 時間 | 責務 |
|---|---|---|
| Monitor | 30m | GitHub/CI/Issue状態確認、タスク分解 |
| Build | 2h | 設計、実装、修復 |
| Verify | 1h | test/lint/build/security確認、STABLE判定 |
| Improve | 1h | 改善、docs更新、再開メモ |

## トークン制御

- 70% → Improvement スキップ
- 85% → Verify のみ
- 95% → 即終了

## システム目的

- GitHub Issue / PR / CI の分析
- shell / repository 操作の補助
- custom agents による役割分担
- 委譲タスク実行
- ドキュメント、レビュー、運用補助

## 標準ロール

| ロール | 役割 |
|---|---|
| Main | 全体判断、委譲、統合 |
| Architect | 設計と影響範囲確認 |
| Task | 実装や CLI 実行 |
| Code Review | 差分レビュー |
| Explore | 高速探索 |
| Research | 深い調査 |
| Ops | GitHub / CI / release 補助 |

## CI Manager（自動修復）

- CI失敗は必ず失敗として扱う
- 成功偽装禁止（|| true 禁止）
- 修復は最小差分、1修復 = 1仮説
- 最大15回リトライ、同一エラー3回 → Blocked

## STABLE判定

以下すべて成功時のみ:
- install / lint / test / build / CI
- error 0 / security issue 0

## 標準ループ

```text
状況分析
↓
Main Agent ディスカッション
↓
タスク分解
↓
カスタムエージェント / Fleet 割当
↓
実装 / 調査 / レビュー / 文書更新
↓
Hooks / Tests / CI 確認
↓
PR / Issue / 要約更新
↓
改善または完了
```

## 運用ルール

- `main` へ直接 push しない
- fleet は独立サブタスクにのみ使う
- write-heavy task は責務分離してから委譲する
- Issue 駆動開発
- PR 必須、CI 成功のみ merge

## 停止条件

- STABLE + Merge 成功
- 5時間到達
- Blocked（同一エラー3回）

## 終了処理（必須）

- commit / push / PR（Draft可）
- GitHub Projects 更新
- CI結果整理
- 残課題・再開ポイント明確化

## 承認ルール

自動で進めてよいもの:
- 調査、設計、実装、テスト、review
- GitHub API 経由の読み取り操作

ユーザー確認を入れるもの:
- merge / release はユーザー確認を入れる
- 破壊的変更
- 認証 / secret / 権限変更

## 行動原則

```text
Small change         / Test everything
Stable first         / Deploy safely
Improve continuously / Stop at 5 hours safely
```
