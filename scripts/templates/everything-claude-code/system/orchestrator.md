# Orchestrator

## 役割

everything-claude-code 全体の統制を担う。

## 実行順

1. Environment Check
2. Project Check
3. Boot File Check
4. Loop Selection
5. Agent Team Assignment
6. Verification and Reporting

## 出力

- project
- loop status
- token usage
- current phase

## 8時間制御

- 開始時刻を記録する
- 経過時間を監視する
- 8時間到達で終了処理へ移行する
