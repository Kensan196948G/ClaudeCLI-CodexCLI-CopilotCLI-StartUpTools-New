# 04-agent-teams — Agent Teams 設計 (v9.0)

## 🎯 目的

ClaudeOS v9.0 を単体 AI ではなく、複数役割を持つ仮想開発組織として運用する。
`/goal` で設定した目標に対し、CTO が状況に応じてパターン A/B/C を自律選択する。

---

## 🧑‍💼 基本チーム構成

| Agent | 役割 |
|---|---|
| CTO | 全体判断・優先順位・/goal 管理・リリース責任 |
| Manager | Issue 管理・進捗管理・Project 同期 |
| Architect | 設計・技術選定・構造レビュー |
| DevAPI | API / Backend 実装 |
| DevUI | Frontend / UI 実装 |
| QA | テスト設計・品質保証 |
| Tester | 実行検証・再現確認 |
| CIManager | GitHub Actions / CI 修復 |
| Security | 脆弱性・権限・秘密情報確認 |
| ReleaseManager | リリース判定・最終報告 |
| CMDB-Agent | 構成管理・依存関係マップ・変更影響分析 |
| Audit-Agent | 変更証跡・ISO/J-SOX 規格準拠・監査レポート |

---

## 🤝 Agent Teams パターン（v9.0 新設）

### パターン A: 並列実装（複数機能の同時開発）

```
Lead: CTO（統制・統合）
Teammate 1: Backend 実装（API / DB / ロジック）
Teammate 2: Frontend 実装（UI / UX）
Teammate 3: テスト設計・検証
```

使用場面: 複数機能の並列実装

### パターン B: 品質強化（CI 失敗修復・リリース前）

```
Lead: CTO（統制・判断）
Teammate 1: バグ修復・CI 修復
Teammate 2: セキュリティレビュー
Teammate 3: 回帰テスト
```

使用場面: CI 失敗 + Security + テスト同時対応

### パターン C: 調査・設計（アーキテクチャ検討）

```
Lead: CTO（統制・意思決定）
Teammate 1: 技術調査
Teammate 2: アーキテクチャ設計
Teammate 3: Devil's Advocate（反証・リスク指摘）
```

使用場面: 大規模設計検討・多観点が必要な場面

---

## 👁 Agent View（v9.0）

```bash
claude agents
```

| アイコン | 状態 |
|---|---|
| ✽ | Working（実行中） |
| ✻ | Needs Input（入力待ち） |
| ✙ | Idle（アイドル） |
| ✔ | Completed（完了） |
| ✘ | Failed（失敗） |

操作: Space（Peek・返信）/ Enter（Attach・直接接続）

**Agent View は監視・観測のみ担当。意思決定は CTO が行う。**

---

## 📊 計測と可視化（v9.0+ 追加）

### 計測 hook

`.claude/claudeos/scripts/hooks/agent-teams-tracker.js` が **PostToolUse** で
`TeamCreate` / `SendMessage` の呼び出しを検出し、`state.agent_teams_usage` に記録する。

記録項目:
- `current_session.team_create_count` / `send_message_count`
- `current_session.teammates[]`（spawn された teammate 名と subagent_type）
- `current_session.patterns_used[]`（現フェーズから推定: Build→A / Verify→B / Monitor→C）
- `history[]`（過去 50 セッション分の集計）

### Dashboard 監視（Agent View 代替）

`claude agents` (TUI) は別端末必須で Claude 内側から起動不可のため、
**Mission Control ダッシュボードを Agent View 代替**として位置付ける。

```bash
node scripts/dashboards/serve-dashboard.js
# → http://localhost:3737/mission-control
```

新規エンドポイント:
- `GET /api/agent-teams` → `state.agent_teams_usage` の集計を返す

Agent Teams タブ内の **Agent Teams Activity バッジ** で以下を 30 秒ごとに自動更新表示:
- 現セッションの TeamCreate / SendMessage 回数
- 現セッションで使用されたパターン
- 直近 7 日のパターン別使用回数

### SessionStart 推奨パターン提示

`session-start.js` hook が起動時に `state.execution.phase` を読み取り、
対応する Agent Teams パターン (A/B/C) を CTO Agent に提示する（強制ではなく指針）。

| フェーズ | 推奨パターン |
|---|---|
| Build / Development | A — 並列実装 |
| Verify / Quality / Repair | B — 品質強化 |
| Monitor / Research / Design | C — 調査・設計 |

---

## ⚖️ Sub-agent vs Agent Teams

| 基準 | Sub-agent（Task） | Agent Teams |
|---|---|---|
| コンテキスト | 結果を呼び出し元に返す | 各自独立ウィンドウ |
| 通信 | 親エージェントへ報告のみ | Teammate 間で直接通信可 |
| トークンコスト | 低 | 高 |
| 使用場面 | Lint 修正・単機能・docs 更新 | 複数機能並列・多観点協調 |

**Agent Teams 使用条件:**

| 場面 | 判断 |
|---|---|
| 複数機能の並列実装 | ✅ パターン A |
| CI + Security + テスト同時 | ✅ パターン B |
| 大規模設計検討 | ✅ パターン C |
| 1 ファイル修正 / Lint / docs | ❌ Sub-agent で十分 |

---

## 🌀 dynamic workflows（第3オーケストレーション階層・v2.1.154+）

`/workflows` は **Claude が書いた JS script を runtime がバックグラウンド実行**し、
数十〜1000 の subagent をオーケストレーションする公式機能（research preview）。
Agent Teams の上位スケール層であり、**tmux / 外部オーケストレータ不要**で機能する。

> ⚠️ **GitHub Actions workflow（`.github/workflows/*.yml`）とは別物。**
> あちらは CI。dynamic workflow は `.claude/workflows/*.js`。混同しないこと。

### 🗺️ 3 階層の使い分け（Sub-agent → Agent Teams → workflows）

| 階層 | プリミティブ | 計画保持 | 中間結果 | スケール | ClaudeOS 用途 |
|---|---|---|---|---|---|
| 1 | Sub-agent (Task) | Claude 毎ターン | context 内 | 数件 | Lint 修正・単機能・docs 更新 |
| 2 | Agent Teams | Claude 毎ターン・相互通信 | 各 window | 数体 | フルスタック協調・CI+Sec+test 同時 |
| 3 | **dynamic workflows** | **script (runtime)** | **script 変数** | **数十〜1000** | **Gate 検証スイープ・大規模監査・Pattern C 調査** |

**第3階層が有利な点**: 中間結果が script 変数に留まり **最終回答だけ context に返る** ため、
Agent Teams の「token 3-5倍」と逆で、5 時間 / token 予算（§13 / §14）に優しい。
runtime に **16 並列 / 1000 agents 上限**が組み込まれ「暴走」を構造的に防ぐ。

### 🎬 起動方法

| 方法 | 使い方 | ClaudeOS 方針 |
|---|---|---|
| バンドル | `/deep-research <問い>` | ✅ Monitor / Pattern C の技術調査に推奨 |
| キーワード | プロンプトに `workflow` の語を含める | ✅ 明示起動。CTO 判断で使用 |
| 保存コマンド | `.claude/workflows/<name>.js` → `/<name>` | ✅ 反復作業を codify |
| ultracode | `/effort ultracode`（全タスク自動 workflow 化） | ❌ **既定化しない**（token 急増・暴走源） |

### 🛡️ ガードレール（CTO 行動ルール）

dynamic workflow は **session 終了で in-progress 分が破棄**され（resume は同一セッション内のみ）、
token をプラン上限に計上する。以下を厳守:

- ✅ **起動可**: token 消費 < 70%（§13）かつ セッション残り ≥ 60 分（§14）
- ❌ **起動不可**:
  - セッション残り < 60 分（終了で成果が破棄される）
  - token ≥ 70%
  - Stabilize / Release フェーズの大規模変更
  - `/effort ultracode` の既定化
- SessionStart hook が `workflows: 起動可 / 抑制` をフェーズ・残時間から自動提示する
- 並列・総数の上限管理（16 / 1000）は runtime に委ねる

### 👁 監視（`/workflows`）

`claude agents`（Agent View）とは別に、workflow 専用のビルトイン監視 UI がある:

```text
/workflows        # 実行中・完了済 run の一覧 → Enter で phase / agent / token / elapsed を確認
```

操作: `p` 一時停止/再開 ・ `x` 停止 ・ `r` agent 再起動 ・ `s` script を保存（コマンド化）

> Agent Teams のような自前ダッシュボードは不要（built-in 監視で足りる）。

### 📦 保存と全プロジェクト配布

`/workflows` → `s` で `.claude/workflows/<name>.js`（project）に保存すると `/<name>` 化される。
project 配置分は TemplateSyncManager 経由で全登録プロジェクトへ配布可能。
（ClaudeOS 専用 workflow の著作は live run 検証を伴うフォローアップで実施）

> 💡 **SSH 越しで migrate / 配布スクリプトを実行する時は `stdbuf -oL -eL node …` を使う**:
> 非 TTY だと Node の stdout がブロックバッファされ、**完走していても出力が出ず「固まった」ように見える**。
> `stdbuf -oL` で行バッファ化すれば即時表示。`timeout N` 併用で安全に切り分けできる。
> 例: `ssh host 'cd <repo> && timeout 120 stdbuf -oL -eL node scripts/setup/migrate-agent-teams.js --apply'`

### 🔌 無効化（必要時）

`disableWorkflows: true`（settings）/ `CLAUDE_CODE_DISABLE_WORKFLOWS=1` / `/config` トグル。
**ClaudeOS 既定では無効化しない（有効状態を維持）。**

### 📝 将来の取り込み候補（ChangeLog メモ）

- **continueOnBlock**（PostToolUse）: 現状 ClaudeOS の guard hook は pre-commit / Stop で動くため適用先なし。将来 blocking PostToolUse を足す時に検討
- **hook `args:[]` exec 形式**: shell を介さず quoting 事故を防ぐ。Win / Linux 両対応の堅牢化として必要時に移行

---

## 🔁 Agent ログフォーマット

```text
[👔 CTO / 最高技術責任者] 判断:
[💻 Developer / デベロッパー] 実装:
[🧪 QA / 品質保証] 検証:
[🔒 Security / セキュリティ] リスク:
[⚙️ DevOps / 運用基盤] CI状態:
[🗄️ CMDB-Agent / 構成管理] 影響範囲分析:
[📋 Audit-Agent / 監査] 証跡確認・規格準拠:
```

---

## 🚫 禁止事項

- Agent 判断なしの merge
- QA 確認なしの Done 移動
- Security 未確認の release
- Release 期の新機能追加
- 同一原因エラーの無限修復（2 回で停止）
