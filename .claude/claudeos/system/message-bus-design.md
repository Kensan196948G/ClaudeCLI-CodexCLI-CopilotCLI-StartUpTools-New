# Message Bus 設計書

**Issue**: #127
**作成日**: 2026-04-15
**ステータス**: Draft — 採用候補案 A（state.json 拡張）

---

## 1. 課題と目的

ClaudeOS v8 の自律開発ループでは、複数の Agent（Orchestrator / Reviewer / QA / DevOps 等）が
並行して動作する場面がある。現状では Agent 間の情報伝達は `state.json` の直接読み書きに依存しており、
以下の問題が発生しうる。

| 問題 | 具体例 |
|---|---|
| 書き込み競合 | 2 Agent が同時に `state.json` を更新 → 一方の変更が失われる |
| メッセージロスト | Producer が書いた結果を Consumer が読む前に上書きされる |
| イベント順序不定 | どの Agent の更新が最新か判断できない |
| デバッグ困難 | Agent 間の通信履歴が残らない |

**目的**: Agent 間の非同期メッセージ交換を安全・追跡可能にする「Message Bus」層を導入する。

---

## 2. トピック設計

| トピック名 | Publisher | Subscriber | 用途 |
|---|---|---|---|
| `phase.transition` | Orchestrator | 全 Agent | フェーズ切替通知 |
| `review.result` | Reviewer / Codex | Orchestrator, Developer | レビュー完了・指摘内容 |
| `ci.status` | DevOps | Orchestrator, QA | CI 結果（pass / fail / running）|
| `rescue.result` | Debugger / Codex | Orchestrator, Developer | rescue 完了・修正案 |
| `stable.verdict` | QA | Orchestrator, CTO | STABLE 判定結果 |
| `evolution.proposal` | EvolutionManager | Orchestrator, CTO | 自己進化提案 |
| `token.alert` | Orchestrator | 全 Agent | Token 残量アラート（70% / 85% / 95%）|
| `time.alert` | Orchestrator | 全 Agent | 残時間アラート（30m / 15m / 10m / 5m）|

---

## 3. 実装アプローチ比較

### 案 A — state.json 拡張（**採用推奨**）

`state.json` に `message_bus` セクションを追加し、トピック別のメッセージキューを持つ。

**メッセージフォーマット**:

```json
{
  "message_bus": {
    "phase.transition": [
      {
        "id": "msg-001",
        "timestamp": "2026-04-15T10:30:00Z",
        "publisher": "Orchestrator",
        "payload": { "from": "Monitor", "to": "Development" },
        "consumed_by": []
      }
    ],
    "ci.status": [
      {
        "id": "msg-002",
        "timestamp": "2026-04-15T10:45:00Z",
        "publisher": "DevOps",
        "payload": { "status": "pass", "run_id": "12345" },
        "consumed_by": ["Orchestrator", "QA"]
      }
    ]
  }
}
```

**メッセージ保持ポリシー**:
- 各トピックで最新 **10 件**を保持（古いものは自動削除）
- `consumed_by` に全 Subscriber が登録されたメッセージは GC 対象

**メリット**:
- 既存インフラで即実装可能（新ツール不要）
- state.json が単一の真実源のまま
- デバッグ・監査が容易（ファイル直読み）

**デメリット**:
- ファイルロックが実装できないと書き込み競合リスクが残る
- 大量メッセージ時のファイルサイズ肥大

---

### 案 B — ファイルベースキュー

`~/.claude/bus/{topic}/{timestamp}-{id}.json` として1メッセージ1ファイル。

**メリット**:
- ファイルシステムの原子性で競合回避
- トピック単位でディレクトリを分離

**デメリット**:
- ファイル数が増大
- 既存の state.json 管理と分離されて二重管理になる

---

### 案 C — Memory MCP 経由

Memory MCP の Entity/Relation グラフをメッセージバスとして使用。

**メリット**:
- 長期記憶と連携（過去メッセージの参照が容易）
- ネットワーク越しの Agent 協調に拡張可能

**デメリット**:
- MCP 接続が前提（オフライン時に動作不可）
- 実装コストが最も高い

---

## 4. 採用推奨案の実装計画

**フェーズ 1（最小実装）**: state.json 拡張

- [ ] `state.json` に `message_bus` セクション追加（スキーマ定義）
- [ ] Orchestrator の publish / consume ヘルパー関数設計（PowerShell / Bash）
- [ ] `phase.transition` と `ci.status` の 2 トピックのみ実装

**フェーズ 2（ユーティリティ化）**:

- [ ] メッセージの GC（古いメッセージ自動削除）
- [ ] `token.alert` / `time.alert` の実装（Orchestrator → 全 Agent 一斉通知）

**フェーズ 3（全トピック実装）**:

- [ ] 全 8 トピックの実装
- [ ] consumed_by トラッキング
- [ ] Bus ビューアーコマンド（`/bus:status` 相当）

**フェーズ 4（オプション）**:

- [ ] Memory MCP への永続化（長期ログ）
- [ ] 外部 MCP 対応の抽象化レイヤー

---

## 5. 受入れ条件

- [ ] 2 つ以上の Agent が同一トピックに publish しても競合しない
- [ ] consume 済みメッセージの再処理が発生しない
- [ ] メッセージ履歴が state.json から確認できる
- [ ] 既存の STABLE 判定・CI フローに影響なし
- [ ] 既存テスト（449件）が全 pass

---

## 6. 移行方針

本設計は **既存の state.json 直接共有を即時廃止しない**。
フェーズ 1 のみ実装して効果を測定してから、フェーズ 2 以降を判断する（最小実装優先原則）。

---

## 7. 参照

- Issue #127 — Message Bus パターン検討・設計起票
- `claudeos/system/orchestrator.md` — Orchestrator の状態管理責務
- `claudeos/system/role-contracts.md` — Agent 間協調パターン
- Anthropic: *Multi-agent coordination patterns*
