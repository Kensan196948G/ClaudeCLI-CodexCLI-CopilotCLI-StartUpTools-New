# Source of Truth Map — ClaudeOS

このファイルは **リポジトリ全体の正本・配備先・生成物・legacy の4分類** を定義する。
迷った場合はここを参照し、編集対象と適用先を必ず確認すること。

---

## 4分類の定義

| 分類 | 意味 | 編集可否 |
|---|---|---|
| **正本** (Source) | 人間が編集する唯一の原本 | ✅ 編集する |
| **配備先** (Deployed) | 正本から同期・展開されたランタイムコピー | ❌ 直接編集禁止 |
| **生成物** (Generated) | スクリプトやツールが自動生成するファイル | ❌ 直接編集禁止（`DO NOT EDIT` ヘッダあり） |
| **Legacy** | 旧版・無効化済み・移行待ち | ⚠️ 読み取り専用扱い、削除/移管を検討 |

---

## ファイル・ディレクトリ別分類表

### ClaudeOS カーネル（agents / skills / commands / rules / hooks 等）

| パス | 分類 | 備考 |
|---|---|---|
| `Claude/templates/claudeos/` | **正本** | ClaudeOS カーネルの唯一の編集元 |
| `.claude/claudeos/` | **配備先** | `Claude/templates/claudeos/` から同期。直接編集禁止 |
| ~~`scripts/templates/claudeos/`~~ | 削除済 (v3.2.45) | `Claude/templates/claudeos/` に一本化完了 |

> **同期コマンド（参考）**: `.\scripts\tools\Sync-Templates.ps1` または手動コピー後に diff 確認

---

### Claude Code 設定ファイル

| パス | 分類 | 備考 |
|---|---|---|
| `Claude/templates/claude/CLAUDE.md` | **正本** | プロジェクト CLAUDE.md の編集元 |
| `Claude/templates/claude/START_PROMPT.md` | **正本** | START_PROMPT の編集元 |
| `Claude/templates/claude/instructions/` | **正本** | 分割インストラクション群の編集元 |
| `CLAUDE.md` (リポジトリルート) | **生成物** | `Build-StartPrompt.ps1` が生成。直接編集禁止 |

---

### PowerShell モジュール

| パス | 分類 | 備考 |
|---|---|---|
| `scripts/lib/*.psm1` (17 modules) | **正本** | 実装の正本。テストは `tests/` に対応ファイルあり |
| `scripts/main/*.ps1` | **正本** | 起動スクリプト |
| `scripts/main/Start-CodexCLI.ps1` | **Legacy** | v3.1.0 以降無効化。`config.json` で `tools.codex.enabled=false` |
| `scripts/main/Start-CopilotCLI.ps1` | **Legacy** | v3.1.0 以降無効化。`config.json` で `tools.copilot.enabled=false` |

---

### 設定・スキーマ

| パス | 分類 | 備考 |
|---|---|---|
| `state.schema.json` | **正本** | runtime state の型定義。スキーマの唯一の正本 |
| `state.json.example` | **正本** | state.json のサンプル。schema に準拠させること |
| `config/` | **正本** | 設定テンプレートと設定ドキュメント |
| `config.json` (実機) | **配備先** | `config/` テンプレートから生成・カスタマイズ |

---

### ドキュメント

| パス | 分類 | 備考 |
|---|---|---|
| `README.md` | **正本** | 外部向け製品説明。統計は `update-readme-stats.js` で自動同期予定 |
| `docs/common/` | **正本** | ツール非依存の共通ドキュメント |
| `docs/claude/` | **正本** | Claude Code 向けドキュメント |
| `docs/codex/` | **Legacy** | Codex 向けドキュメント（Claude 専用化後は参照のみ） |
| `docs/copilot/` | **Legacy** | Copilot 向けドキュメント（Claude 専用化後は参照のみ） |
| `docs/SOURCE_OF_TRUTH.md` (本ファイル) | **正本** | SOT マップ自体 |

---

### テスト

| パス | 分類 | 備考 |
|---|---|---|
| `tests/unit/` (17 files) | **正本** | 単体テスト。各 `scripts/lib/*.psm1` に対応 |
| `tests/integration/` (11 files) | **正本** | 統合テスト |
| `tests/smoke/` (1 file) | **正本** | E2E スモークテスト |

---

### CI / GitHub

| パス | 分類 | 備考 |
|---|---|---|
| `.github/workflows/` | **正本** | CI ワークフロー定義 |
| `reports/` | **生成物** | ループレポート等の出力先。コミット対象外推奨 |
| `logs/` | **生成物** | 実行ログ。コミット対象外 |

---

### Worktree

| パス | 分類 | 備考 |
|---|---|---|
| `.worktrees/` | **配備先** | `WorktreeManager.psm1` が管理する一時 worktree |
| `.claude/worktrees/` | **配備先** | Claude Code 側の worktree 管理領域 |

---

## 編集フロー

```
【カーネル変更】
Claude/templates/claudeos/ を編集
        ↓
.claude/claudeos/ へ同期（Sync-Templates.ps1）

【CLAUDE.md 変更】
Claude/templates/claude/ 配下を編集
        ↓
Build-StartPrompt.ps1 を実行
        ↓
CLAUDE.md（リポジトリルート）が再生成される

【PowerShell モジュール変更】
scripts/lib/*.psm1 を直接編集
        ↓
tests/ の対応テストを更新・追加
        ↓
Invoke-Pester .\tests -CI で検証
```

---

## Legacy 移行計画

| 対象 | 状態 | アクション |
|---|---|---|
| ~~`scripts/templates/claudeos/`~~ | 削除済 (v3.2.45) | ✅ `Claude/templates/claudeos/` に一本化完了 |
| `Start-CodexCLI.ps1` | 無効化済み | legacy/ へ退避 または削除 |
| `Start-CopilotCLI.ps1` | 無効化済み | legacy/ へ退避 または削除 |
| `docs/codex/`, `docs/copilot/` | 参照のみ | アーカイブ明示 |

---

*最終更新: 2026-04-18 — このファイルは変更のたびに更新すること*
