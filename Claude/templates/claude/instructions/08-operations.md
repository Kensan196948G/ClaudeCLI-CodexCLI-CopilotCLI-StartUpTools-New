# 運用制御（ループ・WorkTree・Token・時間・STABLE・禁止事項）

## 自律ループ（Auto Loop Intelligence）

### ループ判断ロジック

- KPI 未達 → ループ継続
- CI 不安定 → Verify / Repair 優先ループ
- 安定状態 → Improvement 縮退
- 残時間に応じてループ短縮

### ループフロー

```
Goal解析 → KPI確認 → 優先順位AI判定 → Issue自動生成 → GitHub Projects同期
→ 開発 → テスト → Codex Review → CI / Actions → 修復 → 再検証
→ STABLE判定 → PR → state更新 → Learning更新 → 次ループ
```

### 可視化要件

- 全プロセス・状態・判断をログとして可視化する
- Agentログを必ず出力する
- 進行フェーズを state.json に反映する

## WorkTree運用

- 1 Issue = 1 WorkTree
- 並列実行可
- main 直 push 禁止
- 統合は CTO または ReleaseManager のみ

## 優先順位

| レベル | 対象 |
|---|---|
| P1 | CI / Security / Data impact |
| P2 | Quality / UX / Test / Review findings |
| P3 | Minor improvement / docs / cleanup |

## Token管理

| フェーズ | 配分 |
|---|---|
| Monitor | 10% |
| Development | 35% |
| Verify | 20% |
| Improvement | 10% |
| Debug | 15% |
| IssueFactory | 5% |
| Release | 5% |

## 時間管理

最大実行時間：5時間

| 残時間 | 対応 |
|---|---|
| < 30分 | Improvement 停止 |
| < 15分 | Verify 縮退 |
| < 5分 | 強制終了 |

## STABLE条件

以下すべてを満たすこと：

- test success
- build success
- CI success
- review OK
- security OK
- blocker なし

## 禁止事項

- 無限ループ
- 未検証 merge
- 原因不明修正
- Token 制御無視
- Goal 外変更
- P1 未解決時の軽微改善優先

## 自動停止条件

- STABLE 達成
- 5時間到達
- Blocked
- Token 枯渇
- Security 検知
- 同一原因多発

## 自己進化システム

### 学習対象

- CI 失敗原因
- Review 指摘
- Debug 履歴
- 修正成功パターン
- Blocked パターン

### 挙動

- 同一失敗 → 回避ルール生成
- 成功パターン → 次回優先適用
- 失敗の多い修正方式 → 優先度低下
