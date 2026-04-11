# Loop Guard

## Role
無限ループ防止と強制停止。全システムに対して最優先で適用される。
Priority: Loop Guard > 全システム (CTO / Architect / Developer の判断より優先)。

## Monitoring (プロジェクトごとに独立管理)

- セッション開始時刻・経過時間
- retry 回数 (PR 単位)
- 同一エラーの連続発生回数
- **no-progress 回数** (同一原因で進展なしが連続した回数)
- **same-diff 再生成検知** (同じ差分を繰り返し生成しているか)
- CI 失敗数 (PR 単位)
- **CI 失敗カテゴリ別集計** (エラー文字列でなくカテゴリで clustering)
- Blocked ステータス継続時間

## Stop Conditions

| # | 条件 | 閾値 | 備考 |
|---|---|---|---|
| 1 | 5時間到達 | elapsed ≥ 300m | セッション開始からの経過時間 |
| 2 | same error 連続 | 3 回 | 直前 3 回のループで同一エラー文字列が一致 |
| 3 | **no-progress 連続** | **2 回** | 修正してもテスト・CI・検証結果が改善しない (新規) |
| 4 | **same-diff regeneration** | 2 回 | 同一ファイルに対し同一差分を再生成 (新規) |
| 5 | CI retry 同一 PR | 5 回 | 同一 PR への Actions 再実行 |
| 6 | rescue 連続失敗 | 3 回 | Codex rescue が同一原因で 3 回失敗 |
| 7 | security issue | critical/high 検知 | 件数不問 |
| 8 | Blocked 継続 | 30 分 | Blocked ステータスが 30 分以上継続 |

**進展判定 (no-progress の定義)**:

次のすべてを満たす場合のみ「進展なし」とカウントする (AND 判定):

- 失敗数 (test + lint 合計) が減っていない
- CI 失敗カテゴリが同一
- 差分が実質空 (コメント・空白のみ、または同一範囲の再生成)

ひとつでも **数量的改善** があれば「進展あり」と判定し、`no_progress_streak` をリセットする。
(例: unit test 失敗 20 件 → 1 件は失敗カテゴリが同一でも「進展あり」なので streak は増えない)

## CI 失敗カテゴリ (clustering 基準)

エラー文字列は揺らぐため、以下カテゴリで clustering する:

- `dependency`
- `lint`
- `type`
- `unit_test`
- `integration_test`
- `build`
- `config`
- `security`
- `flaky`
- `infra`
- `unknown`

同一カテゴリ 3 回連続 → Blocked。

## Actions (実行順序厳守)

1. 新規ループ発火の禁止
2. 実行中 SubAgent への停止通知 (完了待ち)
3. git commit (WIP ラベル付き)
4. `.loop-stop-report.md` 出力
5. `.loop-handoff-report.md` 更新 (再開用 / 次セクション参照)
6. GitHub Projects Status を実態に合わせて更新
7. CTO 通知 (GitHub Issue コメント)

## Output

- `.loop-stop-report.md` — プロジェクトルートに配置、フォーマット固定
- `.loop-handoff-report.md` — 再開時の「前回の停止理由」と「次の第一手」を必ず先頭に記載
  **本ファイルの単独 writer は Loop Guard**。Build / Verify / Improve は直接書き込まず、未完了情報を `state.json.execution.pending` と `state.json.execution.pending_verify` に追記するだけ。Loop Guard が停止時に state.json を読んで本レポートを合成する。

### .loop-handoff-report.md テンプレート

```markdown
## 前回の停止理由
- category: {stop_condition_id}
- reason: {具体的な理由}
- elapsed: {H時間M分}

## 次の第一手 (最優先)
- action: {次に踏むべき1手}
- file: {触るべきファイル}
- expected: {成功判定}

## 未完了の担当分 (ロール別)
- [ ] ...

## 調査済みで棄却した仮説
- ...
```

## state.json 拡張スキーマ (Loop Guard 連携)

Loop Guard は以下の state.json フィールドを読み書きする。
**既存の `docs/common/schemas/state.schema.json` および既存 `state.json` のキー名・enum 値を保持した上で、optional な新フィールドのみ追加する** (backward compatible)。

```json
{
  "execution": {
    "start_time": "ISO8601",
    "elapsed_minutes": 0,
    "remaining_minutes": 300,
    "phase": "Monitor|Development|Verify|Improvement|Debug|Release|STABLE",
    "mode": "light|full",
    "retry_count_by_cause": {},
    "no_progress_streak": 0,
    "same_diff_streak": 0,
    "last_stop_reason": "none",
    "pending": [],
    "pending_verify": []
  },
  "debug": {
    "same_error_retry_count": 0,
    "rescue_retry_count": 0,
    "failure_count_by_category": {},
    "last_failure_category": "none",
    "last_root_cause": "",
    "last_fix_strategy": "none"
  }
}
```

- `execution.phase` は既存 enum (capitalized) を維持する (`current_phase` にリネームしない)
- `last_failure_category` は **debug** 配下 (既存の通り)。execution 配下には置かない
- 新しい optional フィールドは `state.schema.json` にも同時追加する必要がある

**更新タイミング**:
- ループ開始: `execution.phase` 更新
- ループ終了: `elapsed_minutes`, `remaining_minutes` 更新
- 失敗検出: `debug.last_failure_category`, `debug.failure_count_by_category` 更新
- 進展判定: `execution.no_progress_streak` 加算 / リセット
- 差分判定: `execution.same_diff_streak` 加算 / リセット
- 停止時: `execution.last_stop_reason` 保存
- Build/Verify の未完了記録: `execution.pending` / `execution.pending_verify` への追記 (Build/Verify ループが書き、Loop Guard が停止時に読む)
