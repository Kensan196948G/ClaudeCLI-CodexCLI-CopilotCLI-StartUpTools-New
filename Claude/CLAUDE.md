# Claude Code プロジェクト設定

このファイルはプロジェクト単位の Claude Code 運用ポリシーです。
グローバル設定（`05_Claudeグローバル設定`）の方針を継承しつつ、プロジェクト固有の設定を定義します。

## 0. 適用範囲

このプロジェクト設定は、リポジトリルートの `.claude/CLAUDE.md` として配置して使用します。
グローバル設定との優先順位は次のとおりです。

- グローバル設定: 全プロジェクト共通の運用方針
- **プロジェクト設定（本ファイル）: プロジェクト固有の方針（グローバルを上書き可）**

## 1. プロジェクト情報

| 項目 | 内容 |
|---|---|
| プロジェクト名 | {プロジェクト名を記入} |
| 目的 | {プロジェクトの目的を記入} |
| 主な利用者 | {利用者を記入} |
| 技術スタック | {使用技術を記入} |
| 準拠規格 | {ISO27001 / ISO20000 / NIST CSF / J-SOX 等} |
| リポジトリ | {URL} |

## 2. 言語と対応

- 日本語で対応・解説する
- コード内コメントは英語可

## 3. 運用ループ

`Monitor -> Build -> Verify -> Improve` の順で進めます。

| ループ | 時間目安 | 責務 | 禁止事項 |
|---|---|---|---|
| Monitor | 1h | 要件・設計・README 差分確認、Git/CI 状態確認、タスク分解 | 実装・修復 |
| Build | 2h | 設計メモ作成、実装、テスト追加、WorkTree 管理 | ついでの大規模整理、main 直接 push |
| Verify | 2h | test / lint / build / security 確認、STABLE 判定 | 未テストの merge |
| Improve | 3h | 命名整理、リファクタリング、README / docs 更新、再開メモ | 破壊的変更の無断実行 |

### ループ判定の原則

ループ判定は時間ではなく **現在の主作業内容** で行います。
優先順位: `Verify > Build > Monitor > Improve`

### 実運用のコツ

- 厳密な時間切替より、フェーズ完了時の切替を優先
- 小変更なら `Monitor -> Build -> Verify` だけでもよい
- 大変更のときだけ `Improve` と複数エージェントを厚く使う

## 4. STABLE 判定

以下をすべて満たした場合のみ STABLE とします。

- test success
- lint success
- build success
- CI success
- error 0
- security critical issue 0

| 変更規模 | 連続成功回数 | 適用例 |
|---|---|---|
| 小規模 | N=2 | コメント修正・軽微な修正 |
| 通常 | N=3 | 機能追加・バグ修正 |
| 重要 | N=5 | 認証・セキュリティ・DB 変更 |

STABLE 未達は merge / deploy 禁止。

## 5. Git / GitHub ルール

- main 直接 push 禁止
- branch または WorkTree 必須
- PR 必須
- CI 成功のみ merge 許可
- Issue 駆動開発を推奨

### GitHub Projects 状態遷移

`Inbox -> Backlog -> Ready -> Design -> Development -> Verify -> Deploy Gate -> Done / Blocked`

- セッション開始・終了時、各ループ終了時に更新
- 接続不可なら「未接続」または「不明」と明記

### PR 本文の最低限

- 変更内容
- テスト結果
- 影響範囲
- 残課題

## 6. Agent Teams

複雑なタスクでは Agent Teams を活用します。

| ロール | 責務 |
|---|---|
| CTO | 優先順位判断、継続可否、8 時間終了時の最終判断 |
| Architect | アーキテクチャ設計、責務分離、構造改善 |
| Developer | 実装、修正、修復 |
| Reviewer | コード品質、保守性、差分確認 |
| QA | テスト、回帰確認、品質評価 |
| Security | secrets、権限、脆弱性確認 |
| DevOps | CI/CD、PR、Projects、Deploy Gate 制御 |

### SubAgent vs Agent Teams 使い分け

| 判断基準 | SubAgent | Agent Teams |
|---|---|---|
| タスク規模 | 小・単機能 | 大・多観点 |
| トークンコスト | 低 | 高 |
| 使用場面 | Lint 修正・単機能追加 | フルスタック変更・セキュリティレビュー |

Agent Teams 使用禁止: Lint 修正のみ / 小規模バグ修正 / 順序依存逐次作業

## 7. 品質ゲート（CI）

最低限欲しいもの:

- lint
- unit test
- build
- dependency / security scan

CI が未整備なら、未整備であることを先に記録する。

## 8. Auto Repair 制御

- 最大 15 回リトライ
- 同一エラー 3 回で Blocked
- 修正差分なしで停止
- テスト改善なしで停止

## 9. Token 制御

- 70% 到達: Improvement 停止
- 85% 到達: Verify 優先
- 95% 到達: 安全終了

## 10. Worktree の使いどころ

向いている場面:

- 複数機能を並列で触る
- 比較検証したい
- main 作業を汚したくない

不要な場面:

- 1 ファイルの小修正
- ドキュメント更新のみ

## 11. 8 時間到達時の必須処理

1. 現在の作業内容を整理
2. 最小単位で commit
3. push
4. PR 作成（Draft 可）
5. GitHub Projects Status 更新
6. test / lint / build / CI 結果整理
7. 残課題・再開ポイント整理
8. README.md に終了時サマリーを記載
9. 最終報告出力

## 12. 設計原則

- 要件から逆算する（目的、対象ユーザー、規格制約、受入れ条件を先に固定）
- 要件・設計・実装・検証を切り離さない
- 単一の真実を持つ（主システム、責務、廃止対象を明確化）
- 規格と監査を後付けにしない
- 受入れ基準をテストへ落とす
- README は外向けの真実として扱う

## 13. README 更新基準

以下のいずれかが変わったら README を更新する:

- 利用者が触る機能
- セットアップ手順
- アーキテクチャ
- 品質ゲート

過剰更新は不要。外部説明に耐えない README は放置しない。

## 14. 行動原則

```text
Small change         / Test everything
Stable first         / Deploy safely
Improve continuously / Stop at 8 hours safely
Document always      / README keeps truth
```

## 15. 参照先

- グローバル設定: `~/.claude/CLAUDE.md`
- 設計原則: `docs/design-principles.md`
- 運用ループ: `docs/operation-loops.md`
- GitHub 連動: `docs/github-integration.md`
- セッションテンプレート: `docs/session-templates.md`
- README テンプレート: `docs/readme-template.md`
