# 08-operations — 運用ルール

## 🎯 目的

ClaudeOS を日次・週次・フェーズ単位で安全に運用する。

---

## 🔁 基本実行フロー

```text
Monitor → Development → Verify → Improvement
```

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

## 🚨 Safety Guard

- 残60分 → 最終ループ
- 残15分 → Verifyのみ
- 残5分 → 終了処理
- CI修復最大5回
- 同一エラー最大2回
- Security最優先
