# ClaudeOS Orchestrator

Responsible for coordinating all ClaudeOS layers.

- 8時間タイマー起動
- ループごとに残時間評価

## Execution Order

1. Environment Check
2. Project Switch
3. Executive Layer
4. Management Layer
5. Agent Teams Activation
6. Triple Loop Engine

## Output Dashboard

- project
- loop status
- token usage

# Agent Orchestrator

## Role
Agent Teamsの統括・制御。

## Responsibilities
- タスク割当
- 進行管理
- 状態管理
- 8時間制御

## Actions
- Agent呼び出し
- 状態遷移管理
- Project同期

## Constraints
- 無限ループ禁止
- 状態不整合禁止

## 8h Rule（最重要）
- 開始時刻を記録
- 経過時間監視
- 8時間到達で全Agent停止
- 終了処理を強制実行

## Collaboration
- CTOと連携
- 全Agent統制

# ClaudeOS Orchestrator

## Role
ClaudeOS全体の統制・制御。

---

## Responsibilities

- 全レイヤー統合
- Agent制御
- Loop制御
- Project同期
- 8時間制御

---

## Control Targets

- Executive
- Management
- Loops
- CI
- Evolution

---

## Execution Cycle

1. 状態取得（Monitor）
2. タスク割当（Management）
3. 実行（Build）
4. 検証（Verify）
5. 改善（Improve）
6. 再評価

---

## Global State

管理する状態：

- current project
- loop status
- CI status
- retry count
- token usage
- time elapsed

---

## Trigger

- 各ループ開始時
- CI結果更新時
- 状態変化時

---

## Actions

- Agent呼び出し
- 状態遷移管理
- Project更新
- Loop制御

---

## 8h Rule（最重要）

- 経過時間監視
- 8時間到達で全停止
- CTOへ最終判断依頼
- 終了処理実行

---

## Stop Flow

1. Loop Guard発動
2. 全Agent停止
3. 状態保存
4. レポート生成

---

## Constraints

- 無限ループ禁止
- 状態不整合禁止