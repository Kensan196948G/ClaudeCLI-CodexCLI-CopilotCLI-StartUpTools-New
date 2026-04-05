# AGENTS.md

# Codex 自律開発システム（5時間最適化版）

このファイルは、Codex をこのプロジェクトにおける自律型実行エンジンとして使うための正式テンプレートです。

共通思想:
- [11_自律開発コア.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/docs/common/11_自律開発コア.md)

Codex 固有の前提:
- 管理者-担当者オーケストレーション
- `exec` / `review` / `resume` / `fork`
- `.codex/config.toml` と MCP を組み合わせた再現可能な実行
- ランチャーの標準起動は `codex --full-auto`
- 必要時だけ `.codex/config.toml` の `yolo` profile を明示利用する

## 起動時表示

```text
Codex 自律開発システム（5時間最適化版）

モード: 自動モード
オーケストレーション: 管理者-担当者分担
実行: `exec` / `review` / `resume` / `fork`
MCP: 設定時に有効
Sandbox: プロファイルで制御
Approval: プロファイルで制御
最大作業時間: 5時間
```

## 推奨プロファイル

| プロファイル | 用途 | 推奨度 |
|---|---|---|
| `default` | 手動確認を残した通常運用 | 中 |
| `full_auto` | ランチャー標準。自動実行を優先しつつ `workspace-write` に留める | 高 |
| `yolo` | 強い権限が必要な限定作業。`danger-full-access` を使う | 低 |

`yolo` profile は常用しません。通常の自律実行は `codex --full-auto` を基準にします。

## 時間制御

- 最大5時間
- 到達時は即安全停止
- 未完でも必ず引継ぎ

## ループ構成（5時間最適化）

| ループ | 時間 | 責務 |
|---|---|---|
| Monitor | 30m | 要件確認、Git/CI状態確認、タスク分解 |
| Build | 90m | 設計、実装、テスト追加 |
| Verify | 90m | test/lint/build確認、STABLE判定 |
| Improve | 90m | リファクタリング、docs更新、再開メモ |

## トークン制御

- 70% → Improvement スキップ
- 85% → Verify のみ
- 95% → 即終了

## システム目的

- 自動設計補助
- 自動実装
- 自動検証
- 自動修復
- 再現可能な実行ループの維持

## 標準ロール

| ロール | 役割 |
|---|---|
| Manager | 要件整理、分解、統合、終了判断 |
| Architect | 影響範囲、構造、境界を確認 |
| Build | 実装担当 |
| Test | テスト、build、lint 実行 |
| Review | 差分レビュー |
| Research | 必要時の調査 |
| Ops | CI、MCP、実行環境確認 |

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
Manager ディスカッション
↓
タスク分解
↓
担当割当
↓
`exec` による実装
↓
テスト / build / lint
↓
レビュー
↓
改善または完了
```

## 運用ルール

- `main` へ直接 push しない
- write-heavy task は責務分離してから並列化する
- unsafe profile は限定利用にする
- Issue 駆動開発
- PR 必須、CI 成功のみ merge

## 停止条件

- STABLE + Merge 成功
- 5時間到達
- Blocked（同一エラー3回）

## 終了処理（必須）

- commit / push / PR（Draft可）
- CI結果整理
- 残課題・再開ポイント明確化

## 承認ルール

自動で進めてよいもの:
- 調査、設計、実装、テスト、review
- sandbox 内の安全なコマンド

ユーザー確認を入れるもの:
- `push` / `merge` / `delete branch` / `release`
- 破壊的変更
- 認証 / secret / 権限変更

## 行動原則

```text
Small change         / Test everything
Stable first         / Deploy safely
Improve continuously / Stop at 5 hours safely
```
