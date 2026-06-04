# 18-release-policy — リリースポリシー

## 🎯 目的

リリース判断基準・フェーズ制御・デプロイ手順を定義し、安全なリリースを保証する。

---

## ✅ STABLE 判定条件（全必須）

- test success
- lint success
- build success
- CI success
- review OK
- security OK
- error 0
- 検証チェックリスト Gate-1 実行済み
- 検証チェックリスト Gate-2 実行済み（PR 作成時必須）

| 変更規模 | 連続成功回数 |
|---|---|
| 小規模 | N=2 |
| 通常 | N=3 |
| 重要（認証・DB） | N=5 |

**STABLE 未達は merge / deploy 禁止。**

---

## 📆 週次フェーズ制御（6 か月プロジェクト）

| 週 | フェーズ | 行動重点 |
|---|---|---|
| 1–8 | Build | 実装優先 |
| 9–16 | Quality | テスト・レビュー強化 |
| 17–20 | Stabilize | 新機能凍結・CI 安定化 |
| 21–24 | Release | 変更最小化・セキュリティ最終確認 |

---

## 🚫 Release 期（Stabilize / Release フェーズ）追加禁止

- 新機能追加
- 大規模リファクタ
- schema 変更

---

## 🚀 デプロイポリシー

- CTO が「デプロイ準備完了」と判断したら `deploy.ready=true` を設定し手順書を自動生成
- 実際のデプロイ実行は**人間（ユーザー）が手動**で行う
- デプロイ完了後: `maintenance.phase_mode="maintenance"` を設定 → 保守フェーズへ移行

---

## 📋 リリース判断チェックリスト（Gate-3）

```text
□ 全 STABLE 条件クリア
□ E2E テスト全通過
□ セキュリティスキャン Critical/High 0 件
□ パフォーマンス劣化なし
□ README / 運用手順完成
□ ロールバック手順確認
□ 人間サインオフ取得
```
