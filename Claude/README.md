# Claude/ — テンプレート配布ディレクトリ

本ディレクトリは、**新規プロジェクトを ClaudeOS 運用に載せるための配布用テンプレート**です。
本リポジトリ自身の Claude Code 実行時設定を置く `.claude/` とは **役割・使われ方が
まったく異なります**（外部コードレビュー評価 #6 対応）。

## 3 つの Claude 系ディレクトリの違い

| ディレクトリ | 役割 | 使われ方 | 配布対象か |
|---|---|---|---|
| **`Claude/`** (本ディレクトリ) | 他プロジェクトへ配布するテンプレート集 | `Start-ClaudeOS.ps1` が新規プロジェクトに `.claude/` / `CLAUDE.md` を生成する際の source | ✅ 配布される |
| **`.claude/`** | 本リポジトリ自身の Claude Code 実行時設定 | `claudeos/`（カーネル）/ `settings.json`（hooks 設定）/ `worktrees/` が常駐 | ❌ リポジトリ固有 |
| **`docs/claude/`** | Claude Code の利用者向けドキュメント | README 補完、Agents/Skills 索引、コマンドリファレンス | ✅ リポジトリに残存（人間可読） |

## 本ディレクトリの構成

| パス | 用途 |
|---|---|
| `CLAUDE.md` | 配布用 CLAUDE.md 雛形（`{プロジェクト名を記入}` プレースホルダ入り） |
| `templates/claude/` | `.claude/` 配下に配布する設定・hook・agent 雛形 |
| `templates/claudeos/` | ClaudeOS v8 カーネル（loops / system / rules / commands） |
| `templates/linux/` | Linux cron-launcher + report-and-mail スクリプト雛形 |

## 編集時の注意

- 本ディレクトリの変更は、**新規プロジェクトへ配布される基準** になります。実運用中の
  プロジェクトには影響しません（既存 `.claude/` を上書きしない設計）。
- 本リポジトリ自身の挙動を変えたい場合は `.claude/claudeos/` 配下を編集してください。
- `Claude/templates/claude/START_PROMPT-backup/` と `Claude/settings.json` は
  `.gitignore` 済。機密キーを含むため絶対にコミットしないこと。

## 関連

- 配布ロジック: `scripts/main/Start-ClaudeOS.ps1`
- ディレクトリ分類の全体図: [`docs/common/18_ARCHITECTURE.md`](../docs/common/18_ARCHITECTURE.md)
