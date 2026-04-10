# セッション開始・前提条件

## LOOP_COMMANDS

```text
/loop 30m ClaudeOS Monitor
/loop 2h ClaudeOS Development
/loop 1h ClaudeOS Verify
/loop 1h ClaudeOS Improvement
```

4つ全て登録されたら次に進む。

## Codex統合（必須）

本環境では Codex Plugin がインストール済みであることを前提とする。

- `codex-plugin-cc`
- `/codex:*` コマンド利用可能
- Review / Rescue / Status 有効
- Review Gate はリリース直前のみ有効化

### 標準実行

```text
/codex:setup
/codex:status
```

### リリース前のみ

```text
/codex:setup --enable-review-gate
```

## 実行方針

- 設定された時間から5時間作業を厳密に守る
- Monitor、Development、Verify、ImprovementをN回ループ（ループ回数はCTO判断）
- AgentTeams機能を大いに活用する
- Auto Mode による自律開発を実行する
- 全プロセスや状況を可視化する
- ドキュメントファイルも常に確認・更新する
- README.mdは分かりやすく、表とアイコン多用、ダイアグラム図も活用して常に更新する
- GitHub Projectsも常に更新する

## 自律継続ルール（最重要）

本システムは完全自律運用である。以下を厳守すること：

- **フェーズ間でユーザーの確認・承認を求めて停止してはならない**
- 実装完了後は自動的に commit → push → PR → Verify へ進むこと
- 「次に進みますか？」「確認しますか？」等の質問は禁止
- 各フェーズ完了時はログを出力し、即座に次フェーズへ移行すること
- commit / push / PR作成 / merge はすべて自律的に実行すること
- 停止が許されるのは「自動停止条件」に該当した場合のみ

## Agent定義

Agent は以下を唯一の定義ソースとする：

👉 `~/.claude/claudeos/`

### 原則

- 本書内の Agent 名は論理ロール名とする
- 実体の Prompt / Role / Behavior は claudeos 側定義を優先する
- 差異がある場合は claudeos 側を正とする
