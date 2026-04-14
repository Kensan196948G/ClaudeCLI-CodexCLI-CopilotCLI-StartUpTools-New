# Improve Loop

## Role
品質改善・最適化。

---

## Targets

- refactoring
- documentation
- naming
- error handling
- performance

---

## Trigger

- Verify成功後
- STABLE前

---

## Actions

- リファクタリング
- ドキュメント更新
- テスト改善
- **Stop-Doing Check (期日到来時のみ)** — 下記セクション参照

---

## Output

- improved code
- docs

---

## Next

- Monitor Loopへ戻る

---

## 5h Rule

- 改善内容を記録

---

## Stop-Doing Check（四半期点検）

モデル進化により不要になったルール・フック・スクリプトを検出して削減候補を Issue 化する。
Improve ループ開始時に以下を **常に先頭で** 判定する。期日未到来ならスキップし、
通常の Improve 作業へ進む。

### 発火条件

`state.json.improvement.stop_doing_review_date` を読み取り、現在日付（UTC）がこの日付
以降であれば点検を発火する。

state.json が存在しない場合、または `improvement` ブロックが欠損している場合は
**点検を実行しない**（初回は手動初期化または Issue #105 の棚卸し結果で設定する）。

### 実行手順（発火時）

点検フェーズは以下の tool 起動命令列で実行する:

1. **使用履歴収集**（並列可）:
   ```
   Bash("git log --since=90.days.ago --name-only --pretty=format: | sort -u > /tmp/recent-touched.txt")
   Glob(".claude/claudeos/agents/**/*.md")
   Glob(".claude/claudeos/skills/**/*.md")
   Glob(".claude/claudeos/commands/*.md")
   Glob(".claude/claudeos/hooks/*.md")
   Read("./state.json")  # learning.usage_history があれば使用
   ```

2. **分類**（各項目を以下のいずれかに割り当て）:

   | 分類 | 条件 | 対応 |
   |---|---|---|
   | A. 90 日以上未呼び出し | `state.json.learning.usage_history[name].last_invoked < today - 90d` | 削除候補 |
   | B. git blame で 30 日以内 | ファイル作成から 30 日未満 | 猶予期間として除外 |
   | C. `seasonal: true` | フロントマターに明示 | 期間限定として除外 |
   | D. 現モデルで代替可能 | Claude の自己評価（description から判定） | 削除候補（要議論） |

3. **Issue 起票**: 分類 A + D の各項目について、以下を含む Issue を 1 件起票:
   - 項目名とパス
   - 追加された背景（`git blame` + `git log` で追加 PR を特定）
   - 過去 90 日の呼び出し回数（`usage_history` から）
   - 削除候補の根拠（分類 A なら使用実態なし、D なら Claude 内在知識で代替可能）
   - ラベル: `stale-candidate`

4. **state.json 更新**:
   ```
   state.json.improvement.stop_doing_last_run = today
   state.json.improvement.stop_doing_review_date = today + interval_days
   state.json.improvement.stop_doing_candidates_found = <Issue 件数>
   ```

### 誤検出防止

- `learning.usage_history` が未存在または 30 日未満のデータしかない場合は、
  分類 A の判定を無効化する（データ不足）
- 分類 D の判定には低信頼度フラグを付け、Issue 本文に「Claude 自己評価による推定」
  と明記する
- 同一項目への再起票を避けるため、既存 `stale-candidate` Issue が open な場合は
  スキップ

### 運用コスト抑制

- 点検自体が Improve ループの 20% を超えないよう、候補数が 50 件を超えた場合は
  上位 10 件のみ Issue 化し、残りは次回に繰越
- state.json が欠損したセッションでは一切実行しない（無害化）

### 参考

- Anthropic: [Harnessing Claude's Intelligence](https://claude.com/blog/harnessing-claudes-intelligence) パターン 2 "Ask what you can stop doing"
- 関連 Issue: #108 (Dead weight 自動検出) — `learning.usage_history` の書き込み側を担当
- 関連 Issue: #105 (カスタム Agent / Skill 棚卸し) — 初回の手動プロトタイプ
- 関連 Issue: #109 (Frontier-Test 月次ループ) — より広範なモデル能力再評価の発展形

---

## Dead-Weight Detection（日次・軽量）

Stop-Doing Check が四半期の広範棚卸しなのに対し、Dead-Weight Detection は
**毎 Improve ループでの軽量スキャン**。`learning.usage_history` を読んで
未使用項目を自動抽出し、閾値到達で Issue 化する。

### 前提データ

`.claude/claudeos/hooks/usage-history-recorder.md` の PostToolUse フックが
稼働していることが前提。このフックは Agent / Skill / Task 呼び出しのたびに
`state.json.learning.usage_history` を更新する。

フックが未稼働 / state.json が欠損している場合、**Dead-Weight Detection は
スキップ**（無害化）。

### 発火条件

以下をすべて満たした場合に実行:

1. `state.json.learning.usage_history` が存在し、少なくとも 1 カテゴリに 30 日以上
   のデータが蓄積されている
2. `state.json.learning.dead_weight.last_detection_run` が現在時刻 - 24 時間 より古い
   （1 日 1 回まで）
3. Improve ループの持ち時間に 10 分以上の余裕がある

いずれかを満たさない場合はスキップ。

### 実行手順

1. **候補抽出**（並列可）:
   ```
   Read("./state.json")
   Glob(".claude/claudeos/agents/**/*.md")
   Glob(".claude/claudeos/skills/**/*.md")
   Glob(".claude/claudeos/commands/*.md")
   Glob(".claude/claudeos/hooks/*.md")
   ```

2. **判定ロジック**:
   ```
   stale_threshold = state.json.learning.dead_weight.stale_threshold_days (既定 90)
   grace_period = state.json.learning.dead_weight.grace_period_days (既定 30)

   for each file in Glob 結果:
     name = ファイル名から拡張子を除いたもの
     category = ファイルが属するディレクトリ（agents/skills/commands/hooks）
     entry = state.json.learning.usage_history[category][name]

     if entry is None:
       # 記録なし → 2 パターン考えられる
       if ファイルの git log 追加日時 < now - grace_period:
         → 候補（"記録なし + 猶予期間外"）
       else:
         → 除外（"猶予期間内の新規項目"）

     elif entry.seasonal == True:
       → 除外（seasonal フラグ付き）

     elif entry.last_invoked < now - stale_threshold:
       → 候補（"閾値超過未使用"）

     else:
       → 除外（活性項目）
   ```

3. **Issue 起票前のフィルタ**:
   - 既に `stale-candidate` ラベル付きの open Issue が該当項目に対して存在するなら除外
   - `candidates_pending_issue` 配列に既に登録済みのものは除外
   - 検出件数が 50 件超過なら上位 10 件のみ起票、残りは `candidates_pending_issue` に
     繰越

4. **Issue 起票**（最大 10 件）:
   各候補について以下を含む Issue を 1 件起票:
   - ラベル: `stale-candidate`
   - タイトル: `chore: Dead-Weight 候補: {category}/{name} の存廃検討`
   - 本文: 追加日、最終使用、total_count、grace period 適用状況、判定根拠

5. **state.json 更新**:
   ```
   state.json.learning.dead_weight.last_detection_run = now
   state.json.learning.dead_weight.candidates_pending_issue = 繰越リスト
   ```

### 誤検出防止

- 判定は read-only ツール（Read / Glob / Grep）の使用状況は考慮しない
- `learning.usage_history` の記録が 30 日未満しかない場合は実行しない（データ不足）
- Frontier-Test（Issue #109）のような将来ループで「自動発火だが手動承認待ち」状態に
  するため、Issue はあくまで候補であり自動削除は行わない

### Stop-Doing Check との役割分担

| 項目 | Stop-Doing Check | Dead-Weight Detection |
|---|---|---|
| 発火頻度 | 四半期 (90 日) | 日次（Improve ループごと） |
| 粒度 | 広範棚卸し（A/B/C/D 4 分類） | 使用実態のみ（閾値超過 or 記録なし） |
| データ源 | git log / 手動判定 + usage_history | usage_history 専用 |
| 判定コスト | 高（Claude 自己評価を含む） | 低（期日と閾値のみ） |
| 誤検出リスク | 中（Claude 判定が入る） | 低（数値比較のみ） |

両者は共存する。Stop-Doing Check は「モデル進化で不要になったもの」を広く拾う
網であり、Dead-Weight Detection は「日々の使用状況から機械的に拾える低コスト網」。
片方で漏れたものを他方で拾える設計。
