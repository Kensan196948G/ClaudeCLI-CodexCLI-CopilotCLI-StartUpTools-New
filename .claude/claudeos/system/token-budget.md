# Token Budget Manager

## Budget Zones (週次の俯瞰)

| Zone   | Range    | Status                  |
| ------ | -------- | ----------------------- |
| Green  | 0–60%    | Normal development      |
| Yellow | 60–75%   | Reduced build activity  |
| Orange | 75–90%   | Monitor priority        |
| Red    | 90–100%  | Development stopped     |

---

## Per-Task Budget (タスク単位の監視・必須)

週次 zone だけでは「1 タスクで Token を吸い尽くす事故」を防げないため、**タスク単位の予算** も同時に監視する。

| モード | 1 タスクあたり上限 | 超過時の対応 |
|---|---|---|
| **light** | セッション残量の 10% | light 継続 or 中断 |
| **full**  | セッション残量の 35% | full 継続可能、ただし残量 < 50% なら light へ降格 |
| Debug (rescue) | セッション残量の 15% | 超過で rescue 打ち切り |
| Improvement | セッション残量の 10% | 超過で即スキップ |

**監視ポイント**:

- エージェント 1 起動ごとに使用量を記録する
- 返却受領時に累計を `state.json.token.current_phase_used` に加算する
- 1 タスクの累計が上限の 80% を超えたら次エージェント起動前に warning
- 上限到達で即中断。残件は `state.json.execution.pending` に追記する
  (`.loop-handoff-report.md` は Loop Guard 単独 writer のため直接書かない。
  Loop Guard が停止時に state.json から合成する)

---

## Role

トークン使用量制御。週次 zone とタスク単位予算の両方を使う。

---

## Actions

- 使用量監視 (週次 + タスク単位)
- 制限適用
- エージェントごとの最大コンテキスト予算チェック
- タスク単位予算の超過検知

---

## Behavior

- Green → 通常
- Yellow → 軽量化 (light モード優先)
- Orange → Monitor 優先 (新規 full 禁止)
- Red → 開発停止 (Verify と終了処理のみ)

---

## Integration

- Orchestrator と連携 (モード降格の判断材料)
- Loop 制御に反映
- Loop Guard の停止条件 (Token 枯渇) と連動
