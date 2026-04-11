# ClaudeOS v8.0-β — Event Driven Layer (差分仕様書)

> **位置づけ**: 本書は ClaudeOS v7.4 (`/CLAUDE.md`) からの **差分のみ** を定義する。v7.4 本文を置き換えるものではなく、**共存する** 加算レイヤーとして動作する。
>
> **矛盾時の優先**: 本差分書と v7.4 本文が矛盾した場合は **v7.4 本文を正とする**。ただし本書で明示的に「v7.4 §X.Y を上書き」と記載した箇所はその限りではない。
>
> **最終更新**: 2026-04-11

---

## §0. 本書のスコープ

### 本書で「追加」するもの

| 項目 | 追加場所 |
|---|---|
| Event Driven Layer (dynamic /loop + Monitor tool + Channels) | 新概念 |
| `state.json.events` ブロック | state.json 加算 |
| `state.json.kpi.event_response_target_minutes` | state.json 加算 |
| `state.json.priority.weights.blocked_issue` | state.json 加算 |
| `state.json.version` / `state.json.etag` | state.json 加算 (並列書込対策) |
| Event 専用 Agent 起動チェーン (4 パターン) | v7.4 §6 を拡張 |
| Bedrock/Vertex/Foundry フォールバック条件分岐 | 環境判定 |
| Event 応答メトリクスの可視化ルール | 可視化要件 |

### 本書では「触らない」もの (v7.4 をそのまま採用)

| 項目 | 参照先 |
|---|---|
| Time Driven LOOP_COMMANDS (4本) | v7.4 `/CLAUDE.md` §0 ステップ 1 |
| AgentTeams 定義・通常フェーズの起動順序 | v7.4 §6, §7 |
| Token 管理・時間管理・STABLE 条件 | v7.4 §13, §14, §9 |
| Codex 統合 (review / rescue / adversarial) | v7.4 §8 |
| CI Manager・GitHub ルール | v7.4 §10, §11, §12 |
| 禁止事項・自動停止条件 | v7.4 §18, §19 |
| 終了処理・最終報告 | v7.4 §20, §21 |
| 行動原則 | v7.4 §22 |

---

## §1. 設計原則

### 1.1 三層監視モデル

v8 は監視/応答を 3 層に分離する。どの層で何を担うかを明示する。

```
          [外部イベント発生]
                │
    ┌───────────┼───────────┐
    │           │           │
[Channels]  [Monitor]   [dynamic /loop]
 外部 push   local stream   smart polling
    │           │           │
    ▼           ▼           ▼
 session    <task-notif>  ScheduleWakeup
 起床         発火         発火
    │           │           │
    └─────┬─────┴───────────┘
          ▼
   Agent Teams 起動
          ▼
   state.json 更新
```

| 層 | 用途 | 遅延 | コスト | 適用対象 |
|---|---|---|---|---|
| **Channels** | 外部システム (CI/GitHub Actions/webhook) からのリアルタイム push | ms〜秒 | 要外部基盤 | CI failure, security alert, 緊急 PR 通知 |
| **Monitor tool** | ローカル background script の stdout stream | 秒 | session bound | `gh run watch`, `tail -f` 系、Claude セッションがオンライン前提 |
| **dynamic /loop** | Claude が 1分〜1時間で自己ペース判断する smart polling | 分 | token 節約型 | state.json 優先度再評価、backlog triage、PR stale 検知 |

**原則**:

1. **CI failure / security alert は Channels 経路を第一選択** とする (session オフラインでも後追いで捕捉可能)
2. Channels 未整備の場合は **Monitor tool** で `gh run watch` 相当を起動する (session bound)
3. Monitor も不要な "時間で十分" な観点は **dynamic /loop** に任せる
4. **固定 cron** (v7.4 の Time Loop 4 本) は引き続き骨格として維持する。イベント層はその上に重ねる

### 1.2 "Event Driven" の定義

v8 における "Event Driven" は、**dynamic /loop 単独では実現されない**。以下の定義とする。

- **strict event-driven**: Channels または Monitor tool による push 受信。polling ゼロ
- **smart polling**: dynamic /loop による自己ペース polling。polling あり、ただし間隔は状況適応
- **time polling**: v7.4 の固定 cron Loop。骨格として維持

v8 は上記 3 層を併用する。"Event Loop を登録する" と言ったときに、実態がどの層になるかは後述 §3 の判定ルールに従う。

---

## §2. セッション開始シーケンス (v7.4 §0 を上書き)

> ⚠️ **本節は v7.4 `/CLAUDE.md` §0 「セッション開始時の自動実行」を上書き** する。

### 2.1 起動順序 (固定)

以下の順序を厳守する。Event Loop は **Codex setup 完了後** に登録する (項目 10 対応)。

```
Step 1: Time Driven LOOP_COMMANDS 登録  (v7.4 と同じ 4 本)
Step 2: Codex セットアップ確認         (/codex:setup, /codex:status)
Step 3: state.json v8 フィールド検査   (§4 参照)
Step 4: Memory MCP 復元                (前回セッションの継続判断)
Step 5: 環境判定                       (§2.3 参照)
Step 6: Event Driven Layer 登録        (§3 参照)
Step 7: 指示確認チェックリスト出力    (§2.2 参照)
Step 8: Monitor フェーズ開始
```

### 2.2 指示確認チェックリスト (v8 版)

```text
=== ClaudeOS v8.0-β 指示確認 ===
[✅/❌] 01 Time Loop 4本 登録済み
[✅/❌] 02 Codex setup 完了 (認証・shared runtime)
[✅/❌] 03 state.json v8 フィールド存在確認 (events/version/etag)
[✅/❌] 04 Memory MCP 復元 or 新規セッション宣言
[✅/❌] 05 環境判定 (local / Bedrock / Vertex / Foundry)
[✅/❌] 06 Event Driven Layer 登録 (§3 の判定結果)
[✅/❌] 07 可視化プロトコル準備 (Agent ログフォーマット)
[✅/❌] 08 自律継続ルール確認 (ユーザー確認禁止)
[✅/❌] 09 STABLE 判定基準確認 (v7.4 §9)
[✅/❌] 10 終了処理プロトコル確認 (5時間・Token・Blocked)
==============================
```

全項目 ✅ を確認してから Monitor フェーズを開始する。

### 2.3 環境判定

Codex setup 後、以下を実行して実行環境を判定し、`state.json.execution.platform` に記録する。

| 判定結果 | Event Layer の挙動 |
|---|---|
| `local` (Anthropic API) | dynamic /loop は 1分〜1時間の自由選択 ✅ |
| `bedrock` | **dynamic /loop は 10分固定縮退**。Event Layer を Monitor tool 中心に組む |
| `vertex` | 同上 |
| `foundry` (Microsoft) | 同上 |

判定方法: 環境変数 `ANTHROPIC_BEDROCK`, `ANTHROPIC_VERTEX`, `ANTHROPIC_FOUNDRY` の存在 + CLI の version 情報から推定する。不明な場合は `local` として扱い、警告を出す。

---

## §3. Event Driven Layer 登録ルール

### 3.1 Event Loop 候補と推奨実装層

v7.4 の 4 つの観点 (CI / PR / Issue / priority) を、監視層ごとに振り分ける。

| 観点 | 第一選択 | 第二選択 | 第三選択 | 実装例 |
|---|---|---|---|---|
| **CI failure 検知** | Channels | Monitor tool | dynamic /loop | Monitor: `gh run watch` |
| **PR review comment** | Channels | Monitor tool | dynamic /loop | Monitor: `gh pr view --json reviews --watch` |
| **New issue / blocker** | Channels | dynamic /loop | — | dynamic /loop で十分 |
| **state.json priority 再評価** | dynamic /loop | — | — | 純粋に時間駆動で OK |

**判定原則**:

1. Channels が整備済 → Channels 経路を最優先 (後続セッションへの到達保証あり)
2. Channels 未整備かつ session bound で許容可 → Monitor tool
3. 上記いずれも不要な "時間で十分" な観点 → dynamic /loop

### 3.2 dynamic /loop 登録時のプロンプト書式

v8 では Event Loop のプロンプトは **素の英語の短文ではなく、ClaudeOS 文脈を含む日本語の slash command または loop.md 参照** にする (項目 15 対応)。

**❌ 非推奨 (v8 原案にあった書式)**:

```text
/loop check whether CI passed and fix failures if safe
```

**✅ 推奨 (v8.0-β)**:

```text
/loop ClaudeOS Event: state.json を読み込み、priority.weights と pending_events を
       再評価し、優先順位の変動があれば CTO に通知して現在タスクの中断を判定
```

または、`.claude/claudeos/loops/event-*.md` に詳細定義を置き、プロンプトからはファイル参照だけ渡す。

### 3.3 Monitor tool 起動例

CI 監視を Monitor tool で実装する場合の雛形:

```bash
# gh run watch は最新の実行を stream する
# 1 行 1 event で Claude session に push される
gh run watch --exit-status --json status,conclusion,name,url
```

```bash
# PR review comment 監視
gh api graphql -f query='
  subscription { pullRequestReview(owner:"...", repo:"...") { ... } }
'
```

Monitor tool の起動は `TaskCreate` 相当 (persistent: true) で行う。起動時に `state.json.events.monitors[].task_id` に記録する。

### 3.4 Channels 経路 (v8.1 で本実装)

v8.0-β では **定義のみ** で、実装は v8.1 に持ち越す。以下を設計メモとして残す。

- GitHub Actions の failure ステップから Claude session へ push
- webhook 経由で外部サービスから session へ push
- Channel ID の発行と state.json への記録
- 認証: Channel token は環境変数で注入

v8.1 で Channels が有効化されたら、上記 §3.1 表の第一選択が自動的に切り替わる。

---

## §4. state.json v8 スキーマ (加算のみ)

> **重要**: v8 は state.json を **加算的に拡張** する。既存フィールドの削除・リネームは行わない。既存のライブファイルの値は保全する。

### 4.1 追加フィールド

```json
{
  "version": "v8.0-beta",
  "etag": "<auto-generated-hash>",
  "execution": {
    "platform": "local",
    "...v7.4 既存フィールドはそのまま...": null
  },
  "kpi": {
    "event_response_target_minutes": 10,
    "...v7.4 既存 KPI はそのまま...": null
  },
  "priority": {
    "weights": {
      "security": 100,
      "ci_failure": 90,
      "data_risk": 85,
      "test_failure": 75,
      "review_findings": 70,
      "blocked_issue": 68,
      "kpi_gap": 65,
      "technical_debt": 40,
      "minor_ux": 20
    },
    "...current_top_reason はそのまま...": null
  },
  "events": {
    "schema_version": "v8.0-beta",
    "last_event_type": "none",
    "last_event_at": null,
    "last_event_severity": "none",
    "pending_events": [],
    "monitors": [],
    "response_metrics": {
      "total_detected": 0,
      "total_responded": 0,
      "avg_response_minutes": 0,
      "max_response_minutes": 0
    }
  }
}
```

### 4.2 `events.pending_events[]` 要素スキーマ (項目 16 対応)

```json
{
  "id": "evt-20260411-001",
  "type": "ci_failure",
  "severity": "high",
  "detected_at": "2026-04-11T15:30:00+09:00",
  "source": "monitor-tool|dynamic-loop|channels",
  "linked_ref": {
    "issue": null,
    "pr": 66,
    "workflow_run": 123456
  },
  "status": "pending",
  "action_taken": null,
  "resolved_at": null
}
```

- `id` は `evt-YYYYMMDD-NNN` で時系列昇順
- `type` は `priority.weights` のキーと同じ命名
- `status` は `pending | investigating | resolved | escalated | ignored`
- `source` は検知経路を記録 (学習に使う)

### 4.3 `events.monitors[]` 要素スキーマ

```json
{
  "task_id": "task-xxxxxx",
  "purpose": "ci-watch",
  "command": "gh run watch",
  "started_at": "2026-04-11T15:00:00+09:00",
  "persistent": true
}
```

Monitor tool の TaskList 由来 ID を保存。セッション終了時に停止漏れがないか確認する。

### 4.4 並列書込対策 (`version` + `etag`, 項目 17 対応)

- `version`: 固定文字列 `"v8.0-beta"` (スキーマバージョン)
- `etag`: 書込み前の state.json のハッシュ。読込 → 加工 → 書込み時に etag が一致しなければ再読込 merge

**書込み手順** (Time Loop と Event Loop の衝突回避):

```
1. state.json を read → current_etag を計算
2. 必要なフィールドを更新
3. 書込み直前に state.json の現行 etag を再計算して比較
4. 一致 → 書込み / 不一致 → 再 read して 2 からやり直し
5. 書込み後 etag を新しい hash に更新
```

**優先順位ルール** (同時発火時):

- Event 発火による更新 > Time Loop 定期更新
- CTO 判断による更新 > Agent 自動更新
- security severity の更新 > その他すべて

### 4.5 `priority.weights.blocked_issue: 68`

新規追加の重み。`review_findings: 70` と `kpi_gap: 65` の間に配置。「ブロック解除可能性の再確認」を独立した優先度として扱う。

---

## §5. Event 専用 Agent 起動チェーン

v7.4 §6 の起動順序を以下で拡張する。通常フェーズ (Monitor/Development/Verify/Repair/Improvement/Release) はそのまま維持。

| イベント | 起動チェーン |
|---|---|
| **Event: CI Failure** | CTO → Debugger → Developer → QA → DevOps |
| **Event: PR Review** | CTO → Reviewer → Developer → QA |
| **Event: New Issue / Blocker** | CTO → ProductManager → Analyst → Architect |
| **Event: Priority Switch** | CTO → Analyst → ProductManager |
| **Event: Security Alert** | CTO → Security → Debugger → DevOps → CTO |
| **Event: Stale PR Detected** | CTO → ProductManager → DevOps |

起動条件:

- `state.json.events.pending_events` に新要素が追加されたとき
- Monitor tool から `<task-notification>` が届いたとき
- Channels 経路から push を受信したとき (v8.1)

---

## §6. 可視化要件 (v7.4 §01 "4. リアルタイム可視化ルール" を拡張)

v7.4 の 6 タイミングに以下 2 つを追加:

| タイミング | 出力内容 |
|---|---|
| **イベント検知時** | event_id / type / severity / source / linked_ref / detected_at |
| **イベント応答完了時** | event_id / resolved_at / response_delta_minutes / action_taken / target との差分 |

### 6.1 応答遅延メトリクステーブル

ループ完了時に以下の形式でテーブル出力 (項目 25 対応):

```
┌─────────────────────────────────────────────────────────┐
│ Event Response Metrics (this loop)                     │
├─────────┬──────────┬──────────┬─────────┬───────────────┤
│ event_id│ type     │ severity │ delta(m)│ vs target(10m)│
├─────────┼──────────┼──────────┼─────────┼───────────────┤
│ evt-001 │ ci_fail  │ high     │     3.2 │     ✅ under  │
│ evt-002 │ pr_rev   │ medium   │    14.5 │     ❌ over   │
└─────────┴──────────┴──────────┴─────────┴───────────────┘
```

---

## §7. `max_loop_count` の適用範囲明確化 (項目 18 対応)

v7.4 の `execution.max_loop_count: 10` は **Time Loop の メジャーサイクル** (Monitor → Development → Verify → Improvement を 1 単位) にのみ適用する。

Event 応答は別カウンターで管理:

```json
"execution": {
  "max_loop_count": 10,
  "current_loop_count": 6,
  "event_response_count": 14,
  "event_response_limit": null
}
```

- `event_response_count` は累計 Event 応答回数
- `event_response_limit` は上限なし (応答は state.json 書込で事実上制限)
- Event による中断は `current_loop_count` の進行を止めない (Event は割り込み、Time Loop は別ライン)

---

## §8. loop.md の役割 (項目 9 対応)

v8 原案が loop.md を "rule file" と誤記していた点を **訂正**。

**正しい定義**:

- `.claude/loop.md` は **`/loop` を引数なしで呼んだ時のデフォルトプロンプト本文**
- rule file / policy file ではない
- CLI 引数ありの /loop 呼び出しからは **完全に無視される**
- 最大 25,000 bytes

ClaudeOS v8 では、loop.md を **"アイドル時メンテナンス担当者" の指示本文** として使う。CI 安定化、PR review 応答、Issue triage を優先する指示を書く。詳細は `.claude/loop.md` 本体を参照。

---

## §9. 禁止事項 (v7.4 §18 への追加)

v7.4 の禁止事項に以下を追加:

- ❌ **loop.md を "rule file" として使うこと** (公式仕様違反)
- ❌ **Event Loop プロンプトに ClaudeOS 文脈を含めない素の英語短文を使うこと**
- ❌ **Codex setup 完了前に Event Driven Layer を登録すること**
- ❌ **state.json を etag 検証なしで書き込むこと** (並列衝突の原因)
- ❌ **Bedrock/Vertex/Foundry 環境で dynamic /loop の間隔が自動調整されると仮定すること** (10 分固定になる)
- ❌ **Channels 未整備の環境で "Event Driven" を謳って session bound でないことを期待すること**

---

## §10. v8.0-β → v8.1 ロードマップ

| 項目 | v8.0-β | v8.1 |
|---|---|---|
| dynamic /loop (smart polling) | ✅ | ✅ |
| Monitor tool (local stream) | ✅ | ✅ |
| Channels (external push) | 定義のみ | ✅ 実装 |
| state.json.events スキーマ | ✅ | v8.1 で追加拡張可 |
| 環境判定 (Bedrock/Vertex/Foundry) | ✅ | ✅ |
| 応答メトリクス可視化 | ✅ | ダッシュボード統合 |
| マルチプロジェクト Event Loop cap | ❌ (後回し) | ✅ |
| Learning への Event 応答書き戻し | 部分 | 完全 |

---

## §11. 本書のメンテナンス

- v7.4 本文 (`/CLAUDE.md`) が更新されたら、本書の §0.2 参照先の節番号を再確認する
- 新しい Event 観点が必要になったら §3.1 表と §5 チェーンを更新する
- state.json スキーマ拡張は §4 で追跡する
- 本書と v7.4 が矛盾した場合は **v7.4 を正** とする (冒頭の原則)

---

## 参照先

| レイヤー | ファイル |
|---|---|
| v7.4 本文 | `/CLAUDE.md` |
| Orchestrator | `.claude/claudeos/system/orchestrator.md` |
| Loop Guard | `.claude/claudeos/system/loop-guard.md` |
| Token Budget | `.claude/claudeos/system/token-budget.md` |
| Role Contracts | `.claude/claudeos/system/role-contracts.md` |
| Loops | `.claude/claudeos/loops/*.md` |
| Bare /loop default | `.claude/loop.md` |
| Live state | `/state.json` |
| 公式 /loop docs | https://code.claude.com/docs/en/scheduled-tasks |
| 公式 Channels docs | https://code.claude.com/docs/en/channels |

---

**ClaudeOS v8.0-β** は、v7.4 の時間駆動骨格を維持しながら、dynamic /loop + Monitor tool + Channels の三層イベント層を重ね、公式 `/loop` 仕様と正しく整合する差分仕様書である。
