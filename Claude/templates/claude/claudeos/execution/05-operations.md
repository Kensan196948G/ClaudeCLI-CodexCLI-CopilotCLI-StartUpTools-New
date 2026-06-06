# 08-operations — 運用ルール (v9.0)

## 🎯 目的

ClaudeOS v9.0 を `/goal` 駆動・動的判断モードで安全に運用する。

---

## 🔁 基本実行フロー（v9.0 動的判断）

```text
/goal 設定 → CTO 優先順位評価 → 最適行動選択 → 実行 → /goal 達成判定
```

フォールバック: `Monitor → Development → Verify → Improvement`

---

## 👔 CTO 優先順位（v9.0）

| 優先度 | 状態 | 行動 |
|---|---|---|
| 1 | Security Critical | 即時対応 |
| 2 | CI 失敗中 | 修復 |
| 3 | Blocker Issue | 解除 |
| 4 | /goal 直結 Issue | 実装 |
| 5 | 検証不足 | 品質強化 |
| 6 | 改善 | 余裕時のみ |

---

## 🟢 Monitor

確認対象:

- state.json
- GitHub Issues
- GitHub Pull Requests
- GitHub Projects
- GitHub Actions
- backlog.md
- TODO.md
- docs/roadmap.md

出力:

```text
Monitor Report:
- current_phase:
- open_issues:
- active_prs:
- ci_status:
- blockers:
- next_target:
```

---

## 🔨 Development

実施内容:

- Issue選定
- ブランチ作成
- 最小単位実装
- 必要テスト追加
- 変更ログ作成

禁止:

- Release期の新機能開発
- 仕様外の大規模改修
- テストなし修正

---

## ✅ Verify

確認対象:

- lint
- unit test
- integration test
- build
- security check
- PR review
- Codex review

判定:

```text
pass → Improvement or Done
fail → CIManager / Codex Debug
```

---

## 🧹 Improvement

実施内容:

- 小規模リファクタリング
- テスト補強
- ドキュメント更新
- state.json学習更新
- Project同期

---

## 📋 GitHub Projects ステータス

```text
Backlog → Todo → In Progress → Review → Verify → Done
```

| トリガー | 状態 |
|---|---|
| Issue生成 | Backlog |
| 開発開始 | In Progress |
| PR作成 | Review |
| CI実行 | Verify |
| 完了 | Done |

---

## 🚨 Safety Guard（v9.0 Stop Conditions）

```
同一エラー同一原因 2 回連続 → Issue 化して次タスクへ
修復試行 3 回到達           → Blocked
コンテキスト圧迫警告        → 即終了処理
```

- 残 60 分 → 最終ループ
- 残 15 分 → Verify のみ
- 残 5 分 → 終了処理
- Security 最優先
