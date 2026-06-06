# 13-e2e-playwright — E2E テスト・CI/CD 統合指示

## 🎯 目的

Playwright を用いた E2E テストと CI/CD 連携により、全エンドツーエンドの品質を自動保証する。

---

## 🚀 E2E テスト（Playwright 必須）

以下を実施すること。

1. ログイン
2. CRUD
3. 承認フロー
4. CSV アップロード
5. PDF 出力
6. モバイル UI
7. 権限制御
8. エラー画面
9. タイムアウト
10. 多重操作

---

## 🔄 CI/CD 連携指示

GitHub Actions と完全連携。以下を自動実行。

```yaml
Lint
UnitTest
E2E（Playwright）
SecurityScan
Build
DeployCheck
RegressionTest
```

---

## 🧠 自動修復ルール

1. エラー解析
2. 根本原因分析（RCA）
3. 修復
4. 再テスト
5. RegressionTest
6. ログ記録

**上限制御:**
- CI 自動修復: 最大 5 回
- 同一原因エラー 2 回連続 → Issue 化して次タスクへ
- 修復試行 3 回到達 → Blocked

---

## 🤖 AI レビュー統合フロー

```text
開発
 ↓
① /coderabbit:review committed --base main   ← 静的解析（高速・広範）
 ↓
② /codex:review --base main --background     ← 設計・ロジック深層レビュー
 ↓
両方の指摘を統合して修正
 ↓
E2E テスト実行（本ファイル）
 ↓
PR 作成 → CodeRabbit PR レビュー（自動）
 ↓
Critical/High 0 件 → マージ
```

| AI | テスト連携での役割 |
|---|---|
| ClaudeCode | テスト実行・デバッグ・修復・5カテゴリ検証 |
| Codex | 静的解析・改善提案・設計整合性確認 |
| CodeRabbit | PR 差分レビュー・品質ゲート |

---

## 📊 レポート出力

```text
- テスト結果（Pass/Fail 件数）
- 失敗項目（番号・内容）
- 原因分析（RCA）
- 修復内容
- 再発防止策
- セキュリティ影響
- パフォーマンス影響
- 修復成功率
```

---

## 🎯 最終目標

「人間がレビュー承認のみを行う品質」を達成する。

- 高品質 WebUI
- 自律型デバッグ
- セキュア設計
- ITSM / ISO27001 / ISO20000 準拠レベル
