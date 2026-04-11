# Verify Loop

## Role
品質検証と CI 確認。**判定専用** (観測は Monitor ループの責務)。

---

## 明示チェックリスト (Build との境界固定)

Verify は文章ではなく以下チェックリストで判定する。全項目に明示的な PASS/FAIL を付けること。

### 基本チェック (light/full 共通)

- [ ] unit tests: 全件 PASS
- [ ] lint: 新規指摘 0
- [ ] build: exit 0
- [ ] typecheck: 新規エラー 0
- [ ] error 0
- [ ] security critical/high issue 0

### Full モード追加チェック (full モードでは常に必須)

差分サイズに依らず、full モードに入ったタスクはすべて以下を実行する。
(role-contracts §1 により full モードは認証・権限・DB 変更・並列同期などサイズ以外の理由でも発動するため、サイズでゲートしない)

- [ ] **integration tests: PASS**
- [ ] code review (Codex): severity high 指摘なし
- [ ] adversarial-review: 認証 / 権限 / DB / 並列 / リリース直前時は必須
- [ ] CI success (GitHub Actions)

### 変更理由との整合性チェック (必須・Verify 固有)

テスト成功だけで完了としない。以下を明示的に確認する:

- [ ] **変更の目的と修正内容が一致しているか** (例: バグ修正のつもりが挙動変更になっていないか)
- [ ] **受入条件との対応**: Issue / PR 記載の受入条件が満たされているか
- [ ] **削除や移動が意図的か** (不要な副作用ではないか)

1 項目でも不整合があれば Verify は FAIL 扱い。

---

## Trigger

- Build 後
- 修正後

---

## Actions

- テスト実行
- CI 確認
- 品質評価
- 変更理由 ↔ 差分の整合性評価

---

## Output

`.loop-verify-report.md` — **判定専用**。観測ログは書かない (観測は Monitor へ)。

### フォーマット

```markdown
## Summary
- mode: light|full
- result: PASS|FAIL
- reason: {一行}

## Checklist
- [x/~] unit tests
- [x/~] lint
- [x/~] build
- [x/~] typecheck
- [x/~] intent consistency
- [x/~] (full) integration tests
- [x/~] (full) CI success (GitHub Actions)
- [x/~] (full) codex review: severity high 指摘なし
- [x/~] (full) adversarial-review (認証/権限/DB/並列/リリース直前時のみ必須)

## Risks
- {未確認点}

## Next Action
- {PASS なら Improvement or 終了処理 / FAIL なら CI Manager or Debugger へ}
```

---

## Next

- 全項目 PASS → Improve Loop (余力時のみ) or 終了処理
- 1 項目でも FAIL → CI Manager / Auto Repair → Debugger (Codex Rescue)

---

## STABLE Check

Verify のチェックリストが全 PASS かつ連続成功回数が変更規模に応じた N に到達した場合のみ STABLE。

| 変更規模 | 連続成功回数 |
|---|---|
| 小規模 | N=2 |
| 通常 | N=3 |
| 重要 (認証/DB/security) | N=5 |

---

## 5h Rule

- 未完でも評価を残す
- 「Verify 中の未判定項目」は `state.json.execution.pending_verify` に追記する
  (Verify Loop は `.loop-handoff-report.md` を直接書かない。writer は Loop Guard のみ)
