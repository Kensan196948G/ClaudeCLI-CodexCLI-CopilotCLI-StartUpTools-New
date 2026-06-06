---
name: cto-session-start
description: CTO全権委任セッション開始スキル — Monitor→Build→Verify→Improveループを自律実行する
---

# CTO セッション開始スキル

このスキルは ClaudeOS v9.0 の CTO 全権委任モードでセッションを開始するための手順を定義します。

## 実行手順

1. `state.json` を読み込み、前回の目標・KPI 状態を確認する
2. `gh issue list --state open --limit 20` で優先 Issue を確認する
3. `gh run list --limit 5` で CI 状態を確認する
4. CTO 優先順位テーブルに従い最初のアクションを自律選択する
5. `/goal` の達成条件を確認し、Monitor → Build → Verify → Improve をループする

## 優先順位テーブル

| 優先度 | 状態 | 行動 |
|---|---|---|
| 1 | Security Critical 検出 | 即時対応 |
| 2 | CI 失敗中 | 原因分析 + 最小差分修復 |
| 3 | Blocker Issue あり | 解除 |
| 4 | Goal 直結 Issue | 実装 |
| 5 | テスト・検証不足 | 品質強化 |
| 6 | 改善・リファクタ | 余裕がある場合のみ |
