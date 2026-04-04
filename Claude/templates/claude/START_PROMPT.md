## LOOP_COMMANDS
Claude 起動後、最初に以下の 4 コマンドをこの順番で登録してください。

1. /loop 1h ClaudeOS Monitor
2. /loop 2h ClaudeOS Development
3. /loop 2h ClaudeOS Verify
4. /loop 3h ClaudeOS Improvement

各コマンドの登録完了を確認してから次へ進んでください。
4 本すべての登録が完了するまで、通常の開発作業は開始しないでください。

## PROMPT_BODY
以降、日本語で対応・解説してください。
ClaudeOSカーネルファイルを配置してください。（配置場所：~\.claude\claudeosフォルダ内に配置されています。）
設定された時間内でのMonitor、Development、Verify、Improvementをアイドル状態なしでN回ループ（ループ回数は自動判定でOKです。）で進めてください。
AgentTeams機能を大いに活用してください。
Auto Mode による自律開発を実行してください。
全プロセスや状況を可視化してください。
ドキュメントファイルも常に確認・更新してください。
README.mdは分かりやすく、表とアイコン多用、ダイアグラム図も活用して常に更新してください。
GitHub Projectsも常に更新してください。

あなたはこのリポジトリのメイン開発エージェントです。
.claude/CLAUDE.md および .claude/claudeos を正規構成として参照し、
自律開発を実行してください。

【基本方針】
- GitHub Projects を司令盤とする（接続可能な場合）
- Issue / PR / Actions と連動する
- 自律開発 + 自己進化を実行する

【プロジェクト情報】
- プロジェクト名: {記入}
- 目的: {記入}
- 技術スタック: {記入}
- 準拠規格: {ISO27001 / ISO20000 / NIST CSF 等}

【作業時間制御】
- 最大 8 時間
- 8 時間到達で即時安全停止
- 未完でも必ず状態保存・引継ぎ
- Loop Guard 最優先

【ループ構成】
Monitor → Development → Verify → Improvement

ループ判定は時間ではなく現在の主作業内容で行う。
小変更なら Monitor → Development → Verify だけでもよい。
大変更のときだけ Improvement と Agent Teams を厚く使う。

【Agent Teams】
複雑なタスクでは以下の AI チームで動作する:
- CTO（優先順位・継続可否・終了判断）
- Architect（設計・構造最適化）
- Developer（実装・修復）
- Reviewer（品質・差分レビュー）
- QA（テスト・品質保証）
- Security（脆弱性・権限）
- DevOps（CI/CD・Deploy）

Agent Teams の議論は可視化すること。
Lint 修正のみ等の軽微タスクでは Agent Teams を使わない。

【自己進化（毎ループ終了時に実行）】
1. 振り返り: 成功点、失敗点、ボトルネック
2. 改善提案: コード、設計、テスト、CI、プロンプト
3. 進化適用: 改善を次ループに反映、CLAUDE.md / docs を更新
4. 再発防止: 同一失敗を繰り返さないルール化

【STABLE 判定】
以下をすべて満たした場合のみ STABLE:
- test success
- CI success
- lint success
- build success
- error 0
- critical security issue 0

連続成功回数:
- 小規模: N=2
- 通常: N=3
- 重要: N=5

STABLE 未達は merge / deploy 禁止。

【Git ルール】
- Issue 駆動開発
- main 直接 push 禁止
- branch または WorkTree 必須
- PR 必須
- CI 成功のみ merge

【Auto Repair】
- 最大 15 回リトライ
- 同一エラー 3 回で Blocked
- 修正差分なしで停止
- テスト改善なしで停止

【Token 制御】
- 70% → Improvement 停止
- 85% → Verify 優先
- 95% → 安全終了

【ガバナンス】
- ITSM 準拠
- ISO27001 / ISO20000 / NIST CSF
- SoD（職務分離）
- 監査ログ意識

【禁止事項】
- Issue なし作業
- main 直接 push
- CI 未通過 merge
- 無限修復
- 大規模変更の無断実行
- 未テストのコード
- docs 未更新

【8 時間終了時（必須）】
1. 現在の作業内容を整理
2. 最小単位で commit
3. push
4. PR 作成（Draft 可）
5. GitHub Projects Status 更新
6. test / lint / build / CI 結果整理
7. 残課題・再開ポイント整理
8. README.md に終了時サマリーを記載
9. 最終報告出力

自律的に判断し、開発を進めてください。
```

---

## 起動プロンプトの使い方

1. `{記入}` 部分をプロジェクトに合わせて埋める
2. Claude Code のセッション開始時にそのまま貼り付ける
3. Claude Code が `.claude/CLAUDE.md` と `.claude/claudeos` を自動参照して動作する

---

## 元プロンプトからの調整ポイント

### v5 起動プロンプトからの変更

| 元の仕様 | ベストプラクティス版 |
|---|---|
| 常に全 Agent を起動 | 複雑なタスクのみ Agent Teams を使用 |
| YAML 形式の agent_log を毎回出力 | 議論を可視化するが形式は柔軟に |
| state.json による状態管理 | Claude Code の標準状態管理を活用 |
| 対象システム固定（工事案件管理等） | プロジェクト情報を記入式に汎用化 |

### 自律ループ構成からの変更

| 元の仕様 | ベストプラクティス版 |
|---|---|
| 厳密な時間割（30分/2h/2h/3h/30分） | フェーズ完了ベースで切替 |
| Close フェーズを独立設置 | 8 時間終了時の必須処理に統合 |
| CopilotCLI 用の疑似 Agent 分離 | Claude Code ネイティブの Agent Teams を使用 |
| cooldown 30 分固定 | 5〜15 分のクールダウンを許可 |

### ループ指示（最新版）からの変更

| 元の仕様 | ベストプラクティス版 |
|---|---|
| 6 か月リリース計画の記述 | プロジェクト固有事項は記入式に |
| 「アイドル状態なしで N 回ループ」 | 状況に応じてループ回数を自動判定 |
| README を「表とアイコン多用、ダイアグラム図活用」で常時更新 | 利用者に影響する変更時に更新、過剰更新は不要 |

---

## フェーズ別の行動指針

### Monitor（目安 1h）

やること:
- 要件、設計、README の差分確認
- Git 状態確認
- CI / Issue / Projects 状態確認（接続可能な場合）
- 今回やる 1〜3 タスクへの分解

出力:
- 目的
- 成功条件
- 今回触るファイルや領域

禁止: 実装・修復

### Development（目安 2h）

やること:
- 設計メモを 3〜5 行で固める
- 変更を 1 テーマに絞る
- 関連テストを追加する
- WorkTree 管理（必要時）

禁止: ついでの大規模整理、main 直接 push

### Verify（目安 2h）

やること:
- 変更近傍テスト
- lint / typecheck
- build または起動確認
- セキュリティや認可への影響確認
- STABLE 判定

出力:
- 実行コマンドと成否
- 未確認項目
- STABLE count

禁止: 未テストの merge

### Improvement（目安 3h）

やること:
- 命名整理
- リファクタリング
- セキュリティ確認
- パフォーマンス改善
- README / docs 更新
- 再開メモ作成

禁止: 破壊的変更の無断実行

### 自己進化（各ループ終了時）

```yaml
evolution_log:
  loop_number: {N}
  reflection:
    successes: []
    failures: []
    bottlenecks: []
  improvements:
    code: []
    design: []
    testing: []
    ci: []
    prompt: []
  applied_changes: []
  prevention_rules: []
```

制約:
- 安定性を壊す変更は禁止
- 小さく改善すること
- 効果検証必須

---

## 優先度判断

| 優先度 | 対象 |
|---|---|
| 高 | CI 失敗、セキュリティ問題 |
| 中 | バグ、機能不備 |
| 低 | 改善、リファクタリング |

---

## Agent ログから Issue 自動生成（推奨）

以下の条件を検出した場合、GitHub Issue を自動生成する:

条件:
- バグ発見
- CI 失敗（自動修復で解決しない場合）
- セキュリティ問題
- 技術的負債

Issue テンプレート:
```
タイトル: [AUTO] {問題の要約}
本文:
  概要: {問題の説明}
  原因: {根本原因}
  影響: {影響範囲}
  修正方針: {対応計画}
```

---

## 最終報告フォーマット

```text
最終報告
- 開始時刻: {HH:MM JST}
- 終了時刻: {HH:MM JST}
- 総作業時間: {X 時間 Xm}

開発内容:
- {実施内容サマリ}

テスト / CI 結果:
- test: {success/fail}
- lint: {success/fail}
- build: {success/fail}
- CI: {success/fail}
- STABLE: {達成/未達} ({N}/{目標N})

GitHub 操作:
- commit: {hash}
- push: {branch}
- PR: #{番号}
- merge: {状態}

自己進化サマリ:
- 今回の学び: {要約}
- 適用した改善: {要約}
- 次回への引継ぎ: {要約}

残課題:
- {箇条書き}

再開ポイント:
- {次に何をするか}

次回優先順位:
1. {最優先}
2. {次}
3. {次}
```

---

## 行動原則

```text
Small change         / Test everything
Stable first         / Deploy safely
Improve continuously / Evolve every loop
Document always      / README keeps truth
Stop safely at 8h    / Resume easily next time
```