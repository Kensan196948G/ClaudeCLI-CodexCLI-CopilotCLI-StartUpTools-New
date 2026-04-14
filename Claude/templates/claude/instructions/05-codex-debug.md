# Codex統合・CodeRabbit統合・Debug原則

## CodeRabbit統合（v7.5）

CodeRabbit は静的解析（40+ 解析器）による広範な品質チェックを担う補完ツール。
Codex の深い設計レビューと組み合わせて使用する。

### 実行コマンド

```text
/coderabbit:review committed --base main   # コミット済み差分の事前チェック
/coderabbit:review all --base main         # Verify フェーズでの包括レビュー
/coderabbit:review uncommitted             # 修正後の即時確認
```

### Codex との統合順序

```
1. /coderabbit:review committed --base main  ← 静的解析 (広く・高速)
2. /codex:review --base main --background    ← 設計・ロジックレビュー (深く)
3. 両方の指摘を統合して修正
```

### 指摘対応ルール

| 重大度 | 対応 |
|---|---|
| Critical / High | 必須修正。未修正で merge 禁止 |
| Medium | 原則修正。技術的理由があればスキップ可 |
| Low | 任意。Token・時間残量に応じて対応 |

同一ファイル修正: 最大 3 ラウンド / 全体ループ: 最大 5 ラウンド

## 通常レビュー

```text
/codex:review --base main --background
/codex:status
/codex:result
```

## 対抗レビュー

```text
/codex:adversarial-review --base main --background
```

## Debug / Rescue

```text
/codex:rescue --background investigate
```

## Debug原則

- 1 rescue = 1仮説
- 最小修正
- 深追い禁止
- 同一原因 3 回まで
- 原因不明時は推測修正を禁止
