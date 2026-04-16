# Token Budget Manager (v8.2)

Weekly token management with Opus 4.7 (1.35x tokenizer) calibration.

## Budget Zones

| Zone   | Range    | Status                  | v8.2 追加対応 |
| ------ | -------- | ----------------------- | --- |
| Green  | 0–60%    | Normal development      | Effort `xhigh` 維持 |
| Yellow | 60–75%   | Reduced build activity  | 70% で `/compact` 事前発動 (CLAUDE.md §12) |
| Orange | 75–90%   | Monitor priority        | 85% で Effort 強制 `high` (CLAUDE.md §10.5) |
| Red    | 90–100%  | Development stopped     | 95% で安全終了 |

---

## Role

トークン使用量制御 + Opus 4.7 1.35x 補正適用。

---

## Actions

- 使用量監視
- 制限適用
- 1.35x calibration による実効値算出
- `/compact` 事前発動トリガ判定
- Effort 動的切替判定

---

## Behavior

- Green → 通常 (Effort `xhigh`)
- Yellow → 軽量化開始 (70% で `/compact`)
- Orange → Monitor 優先 + Effort `high` 強制
- Red → 開発停止 + 終了処理

---

## Integration

- Orchestrator と連携
- Loop 制御に反映
- PreCompact hook (`claudeos/scripts/hooks/pre-compact.js`) と連動
- suggest-compact (`claudeos/scripts/hooks/suggest-compact.js`) で人間/AI 双方に推奨提示
- notify-stable (`claudeos/scripts/hooks/notify-stable.js`) で重要イベントを通知

---

## Opus 4.7 Calibration (v8.2)

Opus 4.7 は新 tokenizer により従来比最大 1.35x のトークン消費。state.json の
`token.calibration_factor: 1.35` を参照し、各フェーズの実効上限を以下で算出する:

```
effective_phase_budget = (allocation_pct × total_budget) / calibration_factor
```

例: Verify 25% × 100 ÷ 1.35 ≒ 18.5% の実効値で運用する。

### task_budget (beta) 連携

Verify / Improvement / Release では state.json `task_budget.total_tokens`
(既定 128000) を Opus 4.7 ヘッダ `task-budgets-2026-03-13` で渡し、モデル自身の
自己ペーシングと二重管理する。

### Effort 動的切替連動

state.json `effort_strategy.current` を読み、Token 消費率に応じて以下に切り替える:

| Token 残量 | Effort | 備考 |
|---|---|---|
| > 30% | xhigh | 既定 |
| 15–30% | high | low_token_threshold_pct |
| < 15% | medium | force_medium_pct（強制） |

切替判定は `suggest-compact.js` と同じタイミングで行う。
