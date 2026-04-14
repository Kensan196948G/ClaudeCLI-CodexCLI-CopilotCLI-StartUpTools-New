# /team-onboarding

新しいメンバーが ClaudeOS プロジェクトに参加する際のオンボーディングガイドを対話的に提供するコマンドです。

## 実行内容

以下のステップをシーケンシャルに案内します。

### Step 1: 環境確認

```text
以下の環境が揃っているか確認してください：

- Claude Code CLI インストール済み
- Git / GitHub CLI (gh) インストール済み
- Node.js (LTS) インストール済み
- リポジトリへのアクセス権限確認済み
- GitHub Token 設定済み
```

### Step 2: ClaudeOS 設定ファイル配置

プロジェクトの CLAUDE.md を確認し、以下のファイルが正しく配置されているか検証します。

| ファイル | 場所 | 用途 |
|---|---|---|
| `CLAUDE.md` | リポジトリルート | プロジェクト運用ポリシー |
| `state.json` | リポジトリルート | Goal / KPI / フェーズ管理 |
| `.claude/claudeos/` | リポジトリ内 | エージェント定義・コマンド定義 |
| `~/.claude/CLAUDE.md` | グローバル | 全プロジェクト共通設定 |

### Step 3: ループコマンド説明

ClaudeOS は以下の 4 つのループで自律開発を実行します：

| ループ | 時間 | 責務 |
|---|---|---|
| Monitor | 30m | GitHub / CI / Issue の状態確認・優先順位決定 |
| Development | 60m | 設計・実装・WorkTree 管理 |
| Verify | 45m | test / lint / build / CodeRabbit / CI 確認、STABLE 判定 |
| Improvement | 45m | リファクタリング・ドキュメント更新・再開メモ |

### Step 4: Agent Teams 説明

ClaudeOS の Agent Teams は以下のロールで構成されます：

| ロール | 責務 |
|---|---|
| CTO | 最終判断・優先順位・継続可否 |
| ProductManager | Issue 生成・要件整理 |
| Architect | アーキテクチャ設計 |
| Developer | 実装・修正・修復 |
| Reviewer | Codex + CodeRabbit レビュー・コード品質 |
| Debugger | 原因分析・rescue 実行 |
| QA | テスト・回帰確認・品質評価 |
| Security | secrets・権限・脆弱性確認 |
| DevOps | CI/CD・PR・Deploy Gate |
| Analyst | KPI 分析・メトリクス評価 |
| EvolutionManager | 改善提案・自己進化管理 |
| ReleaseManager | リリース管理・マージ判断 |

### Step 5: state.json の読み方

`state.json` はセッションの単一の真実（Single Source of Truth）です：

```json
{
  "goal": { "title": "プロジェクトの目標" },
  "kpi": { "success_rate_target": 0.9 },
  "execution": {
    "phase": "Monitor | Development | Verify | Improvement",
    "remaining_minutes": 300
  },
  "token": { "used": 0, "remaining": 100 }
}
```

### Step 6: 開発フローの把握

```
Issue 起票 → Monitor で優先順位確認
→ Development でブランチ作成・実装
→ commit / push / PR 作成
→ Verify で CI・レビュー確認
→ STABLE 達成 → merge
→ Improvement でドキュメント整備
→ 次の Monitor へ
```

### Step 7: 禁止事項の確認

- `main` への直接 push 禁止
- Issue なし作業禁止
- CI 未通過 merge 禁止
- 無限修復（Auto Repair は最大 15 回）
- Token 超過のまま深掘り継続禁止

### Step 8: 最初のセッション開始

準備完了後、以下を実行してセッションを開始します：

```text
/loop 30m ClaudeOS Monitor
/loop 60m ClaudeOS Development
/loop 45m ClaudeOS Verify
/loop 45m ClaudeOS Improvement
```

## 参照先

| ドキュメント | 場所 |
|---|---|
| プロジェクト設定 | `CLAUDE.md` (リポジトリルート) |
| グローバル設定 | `~/.claude/CLAUDE.md` |
| 運用ループ詳細 | `.claude/claudeos/loops/` |
| Agent 定義 | `.claude/claudeos/agents/` |
| CI Manager | `.claude/claudeos/ci/ci-manager.md` |
