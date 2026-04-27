# 運用制御（ループ・WorkTree・Token・時間・STABLE・禁止事項）

## プロジェクト期間・リリース方針（最優先制約）

| 項目 | 内容 |
|---|---|
| プロジェクト期間 | **6ヶ月**（登録日から半年） |
| 実行方式 | Linux Cron（月〜土）自動実行 |
| 1セッション最大時間 | **5時間** |
| 開発フェーズ配分 | Monitor 30min / Build 2h / Verify 1h15m / Improve 1h15m（ループ回数・優先順はCTO判断で調整可） |
| **本番リリース期限** | **登録から6ヶ月後（厳守）** |

### リリース期限の管理原則

- 本番リリース期限は**絶対守ること**。フェーズの自由化はこの制約の下で行う
- GitHub Projects に「本番リリース」マイルストーンを作成し、6ヶ月後の日付を設定すること
- 毎ループの Monitor フェーズで「リリースまでの残日数」を確認・記録すること
- 残り1ヶ月以内になった場合は Improvement を縮退し、Verify/リリース準備を優先すること
- 残り2週間以内: 新機能開発禁止、バグ修正・安定化のみ
- 残り1週間以内: リリース準備のみ（CHANGELOG・README・タグ付け）

### 進捗管理ルール

- 各セッション終了時に GitHub Projects の進捗を更新する
- 6ヶ月間の開発計画を以下のように分割すること：
  - 1〜2ヶ月目: 基盤整備・主要機能実装
  - 3〜4ヶ月目: 品質向上・テスト整備
  - 5ヶ月目: 統合テスト・バグ修正
  - 6ヶ月目: リリース準備・本番移行

## 自律ループ（Auto Loop Intelligence）

### フェーズ間自動遷移（必須）

各フェーズ完了後、ユーザーの入力を待たずに次のアクションへ自動遷移すること。

| 完了フェーズ | 次のアクション |
|---|---|
| Monitor | → Development（Issue選定 → 実装開始） |
| Development | → commit → push → PR作成 → Verify |
| Verify（成功） | → merge → Improvement または 次ループの Monitor |
| Verify（失敗） | → Repair → 再Verify |
| Improvement | → 次ループの Monitor |

**「次に進みますか？」等のユーザー確認は禁止。自動的に進めること。**

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

## ループ上限（無限ループ防止）

- 最大ループ回数: 10回（Monitor→Development→Verify→Improvementで1回）
- 5時間到達で強制終了（ループ途中でも）
- Token 95%到達で強制終了
- STABLE達成かつ未処理Issueなしの場合は早期終了
- 同一Issueで3ループ改善なし → Blocked判定 → ループ離脱

## Token管理

| フェーズ | 配分 |
|---|---|
| Monitor | 10% |
| Development | 35% |
| Verify | 25% |
| Improvement | 15% |
| Debug/Repair | 10% |
| Release/Report | 5% |

| Token消費率 | 対応 |
|---|---|
| 70% | Improvement 停止 |
| 85% | Verify 優先のみ |
| 95% | 即終了処理（安全停止） |

## 時間管理

最大実行時間：5時間

| 残時間 | 対応 |
|---|---|
| < 30分 | Improvement 停止 |
| < 15分 | Verify 縮退 |
| < 10分 | 終了準備開始 |
| < 5分 | 強制終了 |

## STABLE条件

以下すべてを満たすこと：

- test success
- lint success
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
