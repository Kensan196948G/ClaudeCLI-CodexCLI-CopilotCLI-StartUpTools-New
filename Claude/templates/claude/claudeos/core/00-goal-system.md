# 🎯 ClaudeOS Goal System v9.0

## 目的

ClaudeOS における `/goal` を一元管理する。

全 Agent・CTO・CIManager・Codex・CodeRabbit は
本ファイルの `/goal` 定義を唯一の正本として扱うこと。

---

# 🧠 Goal-Driven Development 原則

ClaudeOS は：

- 固定ループではなく Goal Driven
- `/goal` を最上位命令として扱う
- Goal 未達なら継続
- Goal 達成なら適切に終了
- 暴走は禁止
- Security は常に最優先

---

# 🚀 標準 /goal テンプレート

```text
/goal "
MVP Release Candidate を完成させる。

以下を実施対象とする：
- フロントエンド実装
- バックエンド実装
- データベース実装
- セキュリティ実装
- インフラ構成
- CI/CD構築
- テスト
- ドキュメント整備

優先順位：
1. 動作
2. 安定性
3. セキュリティ
4. 保守性
5. UI改善

完了条件：
1. 全主要画面正常動作
2. API疎通成功
3. 認証認可正常
4. DB CRUD成功
5. CI成功
6. Critical/High脆弱性ゼロ
7. E2E成功
8. README完成
9. Docker起動成功（docker-compose.yml がある場合のみ）
10. ローカル環境再現可能

今回対象外：
- 過剰なUI改善
- Enterprise拡張
- AI最適化
- マイクロサービス化
- 大規模リファクタ

制約：
- 5時間以内
- 修復ループ最大5回
- 同一原因エラー2回まで
- 未検証merge禁止
- Release期の新機能禁止

停止条件：
- MVP完成
- CI成功
- リリース条件達成
- 修復ループ上限到達
- Token枯渇
- Context圧迫
- Security Critical発生

or stop after 20 turns
"
```

---

# 👁 Agent View 必須ルール

```bash
claude agents
```

必ず `/goal` 設定後に実行すること。

---

# 🤖 Agent Teams 必須ルール

## パターンA（並列実装）

- Backend
- Frontend
- QA

## パターンB（品質強化）

- CI修復
- Security
- Regression Test

## パターンC（設計検討）

- Architect
- Research
- Devil's Advocate

---

# 🚦 CTO 優先順位

| 優先度 | 状態 | 行動 |
|---|---|---|
| 1 | Security Critical | 即時対応 |
| 2 | CI失敗 | 修復 |
| 3 | Blocker | 解除 |
| 4 | /goal直結Issue | 実装 |
| 5 | 品質不足 | Verify |
| 6 | 改善 | 余裕時のみ |

---

# 🚨 Global Stop Conditions

```text
同一原因エラー2回 → Issue化
修復3回失敗 → Blocked
5時間到達 → 終了
Token枯渇 → 安全終了
Context圧迫 → 即終了
```

---

# 📊 KPI Gate

| 状態 | 行動 |
|---|---|
| Security Critical > 0 | 強制Verify |
| CI失敗 | 修復 |
| test_pass_rate < 80% | QA強化 |
| blocker > 0 | Blocker解除 |

---

# 📋 全ファイル共通ルール

他 md ファイルでは `/goal` を再定義しない。

記載する場合は以下のみ許可：

```text
詳細は 00-goal-system.md を参照
```
