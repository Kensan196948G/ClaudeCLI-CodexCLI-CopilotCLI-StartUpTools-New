# 🚀 ClaudeOS Boot Sequence

## 概要
ClaudeOS 起動時の初期化シーケンスを定義する。

> 適用注記:
> この内容は ClaudeOS の一般方針であり、このリポジトリでは root `CLAUDE.md` と現行実装を優先する。
> Memory MCP、Issue/PR、CI 設定などが存在しない場合は、その確認ステップは省略する。

## 起動フロー

```
1. 環境検出
   └─ OS / Shell / Git / Node / Python バージョン確認

2. プロジェクト検出
   └─ カレントディレクトリの CLAUDE.md / package.json / pyproject.toml を検索

3. Memory 復元
   └─ Memory MCP / Claude-mem から前回セッションのコンテキストをロード

4. Agent Teams 初期化
   └─ タスクキューに基づきSubAgentを割当

5. ループスケジューラ起動
   └─ monitor-loop / build-loop / verify-loop を登録

6. Dashboard 表示
   └─ startup-dashboard.md を描画
```

## 起動チェックリスト

- [ ] Git リポジトリ確認
- [ ] CI 設定ファイル確認（.github/workflows）
- [ ] 未解決 Issue / PR 確認
- [ ] Memory MCP 接続確認
- [ ] トークンバジェット確認

存在しない仕組みは未対応としてスキップしてよい。

## 起動メッセージテンプレート

```
🧠 ClaudeOS
Claude Code Autonomous Development System

Mode: Auto Mode
Orchestration: Agent Teams
SubAgents: Auto Assignment Enabled
```
