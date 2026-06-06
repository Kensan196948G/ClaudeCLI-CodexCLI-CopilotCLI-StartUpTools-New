# 📈 ClaudeOS Observability — Claude Code OpenTelemetry 連携 (readiness)

Claude Code は実行メトリクス/ログを **OpenTelemetry (OTLP)** で外部にエクスポートできます。
ClaudeOS の Analyst エージェント / Mission Control の KPI パネルに、**ログのパースではなく
実テレメトリ**を供給するための土台です。

> ⚠️ **本ディレクトリは「準備 (readiness)」**です。env テンプレと配線手順を提供しますが、
> ライブの OTLP collector + dashboard 取り込みは別途構築が必要（本バッチでは未構築）。
> collector を立てずに有効化しても export 先が無く無意味なので、collector 準備後に有効化すること。

## 🎯 ClaudeOS が活用したい主なメトリクス/イベント

| シグナル | 何がわかるか | ClaudeOS での用途 |
|---|---|---|
| `claude_code.skill_activated` (`invocation_trigger`) | どの skill が auto-trigger / 手動起動されたか | skills 二層構造の実効性検証（[[skills-two-layer]] の実測） |
| `claude_code.pull_request.count` | 作成された PR/MR 数 | KPI（生産性）・Trust Ledger 補助 |
| `claude_code.active_time.total` | 実作業時間 | セッション効率・5時間枠の実消費 |
| `tool_decision` (`tool_parameters`) | ツール使用判断の内訳 | 自律判断の監査・Audit-Agent |
| `claude_code.at_mention` | @メンション解決 | — |

## 🚀 有効化手順（概要）

1. **OTLP collector を起動**（例: `otelcol-contrib` / Grafana Alloy / lightweight OTLP receiver）。
   - grpc:4317 または http/protobuf:4318 で受信。
2. **env を取り込む**: `otel-env.sh.example` を編集（endpoint を collector に合わせる）し、
   `~/.env-claudeos` に追記するか cron/シェルで `source` してから `claude` を起動。
   - cron 経由の自律セッションに効かせる場合は `cron-launcher.sh` が読む env ファイルに入れる。
3. **dashboard 取り込み**（follow-up）: collector の出力（Prometheus / OTLP→JSON 等）を
   `serve-dashboard.js` の新エンドポイントで読み、Mission Control の KPI/Analyst パネルに表示。

## 📋 注意

- `CLAUDE_CODE_ENABLE_TELEMETRY=1` を settings.json の `env` に直書きしない（collector 不在環境で
  全プロジェクトが無駄な export を試みるため）。**opt-in の env テンプレ**として配布する設計。
- API キー認証時はテレメトリ周りの一部機能が無効化される点に注意（CHANGELOG 参照）。
- 3P プロバイダ（Bedrock/Vertex/Foundry）でも OTLP export 自体は可能。

## 関連

- env テンプレ: [`otel-env.sh.example`](./otel-env.sh.example)
- 出典: Claude Code CHANGELOG v2.1.145 / 152 / 157 / 161、公式 OpenTelemetry / monitoring ドキュメント
- follow-up: dashboard 取り込み（collector → `/api/otel-*` → Mission Control KPI パネル）
