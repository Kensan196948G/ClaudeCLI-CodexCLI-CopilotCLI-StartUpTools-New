# 設定ファイル運用

このリポジトリでは、設定の正本を [config/config.json.template](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/config/config.json.template) とし、実機固有の値だけを `config/config.json` に持たせます。

## 基本ルール

- `config/config.json.template`: リポジトリで共有する基準設定
- `config/config.json`: 各端末で使う実設定
- `config/agent-teams-backlog-rules.json`: Agent Teams backlog 同期時の metadata 推定ルール
- 新しい設定キーを追加したら、先に template を更新する
- 手順書や README は template ベースで説明する

## 初期作成

```powershell
Copy-Item .\config\config.json.template .\config\config.json
Copy-Item .\config\agent-teams-backlog-rules.json.template .\config\agent-teams-backlog-rules.json
```

## `config.json` で編集する代表項目

- `projectsDir`
- `sshProjectsDir`
- `projectsDirUnc`
- `linuxHost`
- `linuxBase`
- `localExcludes`

これらは端末やネットワーク構成に依存するため、template ではプレースホルダのままにします。

## 項目対応表

template のキーを追加・変更した場合は、少なくともこの表に対応があるか確認します。

| template キー | 用途 | 主な参照先 |
|---|---|---|
| `version` | 設定バージョン | `scripts/lib/Config.psm1` |
| `projectsDir` | ローカル起動時のプロジェクトルート | `scripts/main/Start-*.ps1`, `scripts/test/Test-AllTools.ps1` |
| `sshProjectsDir` | SSH 実行時に Windows 側で参照する共有ドライブ | `scripts/main/Start-*.ps1`, `scripts/test/test-drive-mapping.ps1` |
| `projectsDirUnc` | UNC フォールバック | `scripts/test/test-drive-mapping.ps1`, `scripts/test/Test-AllTools.ps1` |
| `linuxHost` | SSH 接続先 | `scripts/main/Start-*.ps1`, `scripts/main/Start-Menu.ps1` |
| `linuxBase` | Linux 側プロジェクトルート | `scripts/main/Start-*.ps1`, `README.md` |
| `localExcludes` | ローカル選択から除外するディレクトリ | `scripts/lib/LauncherCommon.psm1` |
| `tools.defaultTool` | 統合ランチャーのデフォルト | `scripts/main/Start-All.ps1` |
| `tools.claude.*` | Claude Code の起動設定 | `scripts/main/Start-ClaudeCode.ps1`, `docs/claude/*` |
| `tools.codex.*` | Codex CLI の起動設定 | `scripts/main/Start-CodexCLI.ps1`, `docs/codex/*` |
| `tools.copilot.*` | GitHub Copilot CLI の起動設定 | `scripts/main/Start-CopilotCLI.ps1`, `docs/copilot/*` |
| `ssh.*` | SSH 実行まわりの補助設定 | `config/config.json.template`, 将来の SSH 共通化拡張 |
| `logging.*` | ログ出力設定 | `scripts/lib/LogManager.psm1` |
| `backupConfig.*` | 設定バックアップ制御 | `scripts/lib/Config.psm1` |
| `recentProjects.*` | 最近使用履歴 | `scripts/lib/Config.psm1` |
| `agent-teams-backlog-rules.json` | backlog metadata 自動付与ルール | `scripts/tools/Sync-AgentTeamsBacklog.ps1`, `TASKS.md` |

## 更新チェック手順

1. `config/config.json.template` を更新する
2. この README の対応表を更新する
3. `scripts/lib/Config.psm1` のスキーマ検証を更新する
4. 関連する `docs/*` と `README.md` を更新する
5. `Invoke-Pester .\tests` を実行する

## Agent Teams backlog ルール

`scripts/tools/Sync-AgentTeamsBacklog.ps1 -ApplyMetadata` は、`config/agent-teams-backlog-rules.json` を読んで `TASKS.md` の自動抽出項目へ `Priority` / `Owner` / `Source` を付与します。

- 共通ルールを見直す場合は `config/agent-teams-backlog-rules.json` を更新する
- 新規端末では template から実ファイルを作成する
- 変更後は `.\scripts\tools\Sync-AgentTeamsBacklog.ps1 -Action sync -ApplyMetadata` を実行する

## ツール設定の基準

- Claude Code: `tools.claude`
- Codex CLI: `tools.codex`
- GitHub Copilot CLI: `tools.copilot`

Copilot の基準コマンドは `gh copilot` です。

```json
"copilot": {
  "enabled": true,
  "command": "gh",
  "args": ["copilot"],
  "env": {}
}
```

## 関連ドキュメント

- [docs/common/07_設定運用ガイド.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/docs/common/07_設定運用ガイド.md)
- [README.md](/D:/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/README.md)
