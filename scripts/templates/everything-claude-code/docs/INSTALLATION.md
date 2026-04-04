# 導入手順書

## 1. 目的

この文書は `everything-claude-code` を Claude Code プロジェクトへ導入し、迷わず使い始められる状態を作るための手順書です。

## 2. 導入前確認

- 対象プロジェクトに `.claude/` を配置できること
- 既存の `CLAUDE.md`、`agents`、`skills`、`rules` がある場合、何を正規とするか決まっていること
- 既存運用と衝突しそうな command や hooks がないか確認すること

## 3. 導入方式

### 最小導入

対象:

- 既存プロジェクトに少しずつ取り込みたい場合
- まず command と skill だけ試したい場合

コピー対象:

- `rules/`
- `commands/`
- 必要な `skills/`

### 標準導入

対象:

- 通常のチーム開発
- 実装、検証、文書更新まで通しで使いたい場合

コピー対象:

- `agents/`
- `skills/`
- `commands/`
- `rules/`
- `hooks/`
- `scripts/`

### 完全導入

対象:

- `everything-claude-code` をプロジェクト標準にしたい場合
- 複数人で同じ構成を使いたい場合

コピー対象:

- `everything-claude-code` 一式

## 4. 初期セットアップ手順

1. 対象プロジェクトの `.claude/` 配下へ必要な構成を配置する
2. `README.md` を読んで全体像を把握する
3. `rules/common/` を確認して最低限の原則を揃える
4. 対象技術に対応する skill を選定する
5. よく使う command を決める
6. 必要なら agent を追加する

## 5. 最初に選ぶとよい skill

### 共通

- `search-first`
- `verification-loop`
- `security-review`

### バックエンド中心

- `backend-patterns`
- `api-design`
- `database-migrations`

### フロントエンド中心

- `frontend-patterns`
- `e2e-testing`
- `update-docs`

### Python

- `python-patterns`
- `python-testing`

### Java / Spring Boot

- `springboot-patterns`
- `springboot-security`
- `springboot-verification`

## 6. 初回セッションの流れ

1. `search-first` を読む
2. `/plan` を使って作業範囲を整理する
3. 対応 skill を 1 から 3 個選ぶ
4. 必要なら対応する agent を併用する
5. 実装またはレビューを進める
6. `/verify` で検証する
7. `/update-docs` で README とメモを同期する

## 7. 導入後の定着ポイント

- 小変更でも `/verify` を省略しない
- README と実装差分を放置しない
- 重複した rules や skills を増やしすぎない
- 「正規構成は `everything-claude-code`」を維持する

## 8. 保守方針

- 新しい skill を追加するときは既存 skill と責務が重複しないか確認する
- 新 command を追加するときは既存 command と名前や用途が被らないか確認する
- hooks は一気に増やさず、失敗時の挙動が読めるものから有効化する
