# 🚀 ClaudeOS v8.5 Ultimate — Modular Prompt Pack

## 🎯 目的

このフォルダは、ClaudeOS v8.5 Ultimate（完全統合版）を用途別に分割したプロンプト／設計ファイル群です。

Claude Code / OpenCode / Codex 補助運用などで、必要な領域だけを読み込ませやすくすることを目的とします。

---

## 📁 推奨読み込み順

```text
_header.md
session-startup.md
core-architecture.md
state-json-spec.md
agent-teams.md
codex-debug.md
github-actions-ci-manager.yml
ai-dev-factory.md
operations.md
termination-reporting.md
```

---

## 🧠 ClaudeOS v8.5 Ultimate の本質

```text
AIが開発するのではない。
AIが開発組織そのものになる。
```

---

## 🔥 最重要原則

- 止まらない
- ただし暴走しない
- 必ず検証する
- 未検証 merge 禁止
- Security は常に最優先
- Release 期は新機能禁止

---

## ⏱ 基本制約

| 項目 | 内容 |
|---|---|
| 実行時間 | 最大5時間（300分） |
| ループ最大 | 3回 |
| CI修復 | 最大5回 |
| 同一エラー | 最大2回まで |
| プロジェクト期間 | 6ヶ月固定 |
| 実行フロー | Monitor → Development → Verify → Improvement |
