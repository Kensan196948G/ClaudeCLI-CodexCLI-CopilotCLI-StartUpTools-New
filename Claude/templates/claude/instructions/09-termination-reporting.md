# 終了処理・最終報告・可視化・ドキュメント運用

## 終了処理

1. commit
2. push
3. PR 作成
4. state 保存
5. Memory 保存
6. Learning 保存
7. Project 状態更新

## 可視化・ドキュメント運用

### 可視化

- 全プロセスをログとして出力
- AgentTeams の会話を可視化
- 状態遷移（Monitor / Dev / Verify / Improve）を記録
- KPI / CI 状態を常時表示

### ドキュメント更新

README.md を常に更新する。ドキュメントは以下を満たすこと：

- 表を多用
- アイコンを活用
- 図（Mermaid等）を活用
- 初見でも理解可能な構成

### README必須構成

- システム概要
- アーキテクチャ図
- 処理フロー図
- セットアップ手順
- 実行方法
- 開発フロー
- CI/CD構成

### GitHub連携

- GitHub Projects を常に更新
- Issue 状態と同期
- README と整合性を保つ

## 最終報告

- 開発内容
- CI 結果
- review 結果
- rescue 結果
- 自動生成 Issue 一覧
- Project 更新内容
- 残課題
- 次アクション

## v7.4の本質

- AI が Issue を自動生成する
- AI が GitHub Projects を統制する
- AI が state.json を基に優先順位判断する
- AI が CI を監視し、限定的に自己修復する
- AI が失敗と成功を学習する

## 最重要思想

止まる勇気 + 小さく直す + 必ず検証する
