# Agent Teams — Light Mode (reference, non-normative)

> **位置づけ**: 本書は ClaudeOS v7.4 / v8.0-β の Agent Teams 定義に対する **リファレンス** である。既存の運用規約を強制的に上書きしない。小規模タスク向けに「軽量召集」の選択肢を明示することが目的。
>
> **矛盾時の優先**: 本書と CLAUDE.md / v8-delta.md が矛盾した場合は **本書を無視** する。

## なぜ Light モードが必要か

v7.4 / v8.0-β の Agent Teams は 12 役割フルセット (CTO / ProductManager / Architect / Developer / Reviewer / Debugger / QA / Security / DevOps / Analyst / EvolutionManager / ReleaseManager) を想定する。以下の場面では全員召集はトークン浪費になる:

- 1 ファイルの軽微なバグ修正
- lint / format の自動修正
- ドキュメントのタイプミス修正
- README の小改訂
- 依存関係の単純なバージョン更新

こうした小規模タスクにはコアの 3 役割だけで十分なケースが多い。

## Light モード定義

### 構成

```
[CTO] → [Developer] → [QA]
```

| 役割 | 最低限の責務 |
|---|---|
| 🧠 CTO | 実行可否の判断、スコープ外に流れ出さない制御 |
| 👨‍💻 Developer | 実装、最小差分の適用 |
| 🧪 QA | test/lint/build のローカル検証、STABLE 判定（N=2） |

**Reviewer / Security / Architect / Debugger は呼ばない**。必要になったら Full モードへ昇格する。

### 適用判定フロー

```
タスク受領
  │
  ▼
 変更ファイル数 ≤ 2 ?
  │  yes → 変更行数 ≤ 50 ?
  │         │  yes → セキュリティ/認証/DB 変更を含まない ?
  │         │         │  yes → Light モードで進める
  │         │         │  no  → Full へ昇格 (Security 必須)
  │         │  no  → Full へ昇格
  │  no  → Full へ昇格
```

### Light → Full 昇格条件

以下のいずれかに該当した時点で即 Full モードへ切替える:

1. Codex review で severity: medium 以上の指摘が出た
2. CI が失敗し、原因が 1 ファイルで閉じない
3. セキュリティ / 認証 / 権限 / DB スキーマに触れる変更が発生した
4. テスト失敗の原因切り分けに 3 回以上の rescue が必要と判断した
5. スコープが拡張し、変更ファイル数 ≥ 3 または変更行数 ≥ 50 になった
6. 複数 Issue に影響する変更であることが判明した

## STABLE 判定の調整

Light モードでは STABLE 連続成功回数を **N=2** に緩和する (v7.4 §9 の「小規模」定義と同じ)。

| 項目 | Light | Full (通常) | Full (重要) |
|---|---|---|---|
| 連続成功回数 | N=2 | N=3 | N=5 |
| Codex review | 省略可 | 必須 | 必須 |
| adversarial-review | 省略 | 条件付き | 必須 |

## Agent Teams 使用禁止場面 (再掲)

以下は Light モードですら召集しない。**SubAgent 単独で処理する**:

- Lint 修正のみ
- フォーマット修正のみ
- ドキュメントのタイプミス修正のみ
- 明らかな一行バグ修正

## トークン節約効果の目安

| モード | 召集役割数 | 1 タスクあたりの概算トークン |
|---|---|---|
| SubAgent 単独 | 1 | 低 |
| **Light** | 3 | 中 (Full の約 1/4) |
| Full (通常) | 6〜8 | 高 |
| Full (重要) | 12 | 最高 |

Light モードは「ほぼ毎回 Full を召集している」状況に対する節約案として提案する。実測値ではなく設計意図上の目安。

## 本書の採用条件

- 本書は **リファレンス** である。既存の運用規約と共存し、強制しない
- プロジェクトごとに採用する/しないを決められる
- 採用する場合は `CLAUDE.md` の Agent Teams セクションから本書を参照する
- 採用しない場合は本書の存在を無視してよい

## 関連ドキュメント

- `CLAUDE.md` §6 Agent Teams — 本書の上位規約
- `.claude/claudeos/system/role-contracts.md` — 役割の I/O プロトコル
- `.claude/claudeos/system/v8-delta.md` — §5 Event 専用 Agent 起動チェーン
