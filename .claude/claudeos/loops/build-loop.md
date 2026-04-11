# Build Loop

## Role
設計・実装を行う開発フェーズ。**実装専用** (検証は Verify に委ねる)。

---

## 明示チェックリスト (Verify との境界固定)

Build は以下を満たしたらループを抜けて Verify へ渡す。Build 内で最終検証は行わない。

- [ ] 対象ファイル境界が宣言済み (並列時は排他)
- [ ] 担当外ファイルに触っていない
- [ ] 1 論理変更 = 1 コミット (論理的完了単位コミット)
- [ ] 新規コードに対応するテスト or 既存テストでカバー
- [ ] ローカルで build が通る
- [ ] main 直接 push なし

---

## Steps (light/full 共通)

1. Design (full のみ / light はスキップ)
2. Foundation
3. Core Implementation
4. Integration
5. Tests

---

## 並列実行時の安全ルール

並列起動時の規約 (担当ファイル境界 / 共有ファイルの単独 writer / 終了条件 3 系統) は
`system/role-contracts.md §4` を **唯一の真実** とする。
本ファイルはルールを複製せず、上記契約に従うことのみ規定する。

---

## Rules

- **論理的完了単位でコミット** (ステップ単位ではなく論理単位)
- WorkTree で作業
- main へ直接 push 禁止
- 1修復 = 1仮説 (CI 失敗対応でも守る)

---

## Trigger

- Monitor 正常時
- Verify OK 後のフォロー実装

---

## Actions

- 実装
- 修正
- テスト追加

---

## Output

- code changes
- commits (論理的完了単位)

---

## Next

- Verify Loop へ

---

## 5h Rule

- 未完でも commit を残す
- 「次に書くべき 1 関数」は `state.json.execution.pending` に追記する
  (Build Loop は `.loop-handoff-report.md` を直接書かない。writer は Loop Guard のみ)
