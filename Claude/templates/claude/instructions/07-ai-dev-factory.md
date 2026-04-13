# AI Dev Factory・GitHub Projects連携

## AI Dev Factory

### 目的

AI Dev Factory は、開発・検証・レビュー結果から次の Issue を自動生成し、GitHub Projects へ反映する自律バックログ工場である。

### Issue生成条件

- KPI 未達
- CI failure
- build failure
- test failure
- Codex review 指摘
- CodeRabbit review 指摘（Critical/High）
- Security findings
- TODO / FIXME 検出
- カバレッジ不足
- ドキュメント欠落
- リファクタ対象の継続蓄積

### Issue生成禁止条件

- 既存 Issue と重複
- 目的不明
- 再現条件なし
- 期待結果なし
- P1 未解決中の軽微改善

### Issueテンプレート

```text
Title: [P1/P2/P3] 短い要約

Summary:
- 何が起きているか
- 何を直すべきか

Reason:
- 発生源（CI / Codex Review / CodeRabbit / KPI / Security / TODO）

Acceptance Criteria:
- [ ] 再現条件が明確
- [ ] 修正条件が明確
- [ ] テスト条件が明確
- [ ] 完了判定が明確

Project Sync:
- Project: <GitHub Project Name>
- Status: Todo
- Priority: P1/P2/P3
- Owner: Agent Role
```

## GitHub Projects連携

### 運用原則

- 生成した Issue は GitHub Projects に必ず紐付ける
- Status / Priority / Owner / Iteration を同期する
- Issue 完了時に Project 状態も更新する

### 標準ステータス

Backlog → Todo → In Progress → Review → Verify → Blocked → Done

### 自動連携ルール

| トリガー | ステータス |
|---|---|
| 新規 Issue 生成 | `Backlog` または `Todo` |
| 開発着手 | `In Progress` |
| CodeRabbit / Codex review 中 | `Review` |
| QA / CI 確認中 | `Verify` |
| 依存待ち / Security blocker | `Blocked` |
| マージ完了 | `Done` |
