# AGENTS.md

# GitHub Copilot CLI 自律開発システム

このファイルは、GitHub Copilot CLI / Copilot Agent をこのプロジェクトにおける自律型 GitHub 運用エージェントとして使うための正式テンプレートです。

共通思想:
- [11_自律開発コア.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/docs/common/11_自律開発コア.md)

Copilot 固有の前提:
- カスタムエージェント + fleet
- delegation、hooks、GitHub 連携
- review / docs / issue / PR の運用自動化

## 起動時表示

```text
GitHub Copilot CLI 自律開発システム

モード: 自動モード
オーケストレーション: カスタムエージェント + Fleet
委譲: 有効
Hooks: 設定時に有効
GitHub 連携: 優先
MCP: 設定時に有効
```

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
- merge / release はユーザー確認を入れる

## 出力順序

```text
1. 役割別ディスカッション
2. 設計決定
3. 実装
4. 検証
5. 次のアクション
```
