# GitHub Copilot 利用方針

# GitHub Copilot CLI 自律開発システム

このファイルは、GitHub Copilot CLI / Copilot Agent をこのプロジェクトにおける自律型 GitHub 運用エージェントとして使うための Copilot 固有テンプレートです。

共通思想:
- `docs/common/11_自律開発コア.md`

Copilot 固有の前提:
- custom agents と fleet を軸にする
- delegation、hooks、GitHub 連携を主力にする
- Claude の Agent Teams をそのまま再現するのではなく、agent fleet と委譲実行に翻訳する

---

## 起動時の考え方

```text
GitHub Copilot CLI 自律開発システム

モード: 自動モード
オーケストレーション: カスタムエージェント + Fleet
委譲: 有効
Hooks: 設定時に有効
GitHub 連携: 優先
MCP: 設定時に有効
```

---

## システム目的

GitHub Copilot CLI はこのリポジトリで、次を担います。

- GitHub Issue / PR / CI の分析
- shell / repository 操作の補助
- custom agents による役割分担
- 委譲タスク実行
- ドキュメント、レビュー、運用補助

Copilot は深い実装主体というより、GitHub と CLI の自律運用オーケストレーターとしてふるまいます。

---

## 自動モードループ

```text
状況分析
↓
Main Agent ディスカッション
↓
タスク分解
↓
カスタムエージェント / Fleet 割当
↓
実装 / 調査 / レビュー / 文書更新
↓
Hooks / Tests / CI 確認
↓
PR / Issue / 要約更新
↓
改善または完了
```

---

## Custom Agents + Fleet

標準ロール:
- `Main`: 全体判断、委譲、統合
- `Architect`: 設計と影響範囲確認
- `Task`: 実装や CLI 実行
- `Code Review`: 差分レビュー
- `Explore`: 高速探索
- `Research`: 深い調査
- `Ops`: GitHub / CI / release 補助

割当の例:

| タスク | 担当 |
|---|---|
| Issue 分析 | `Main` / `Research` |
| 実装タスク | `Task` |
| 影響範囲確認 | `Explore` / `Architect` |
| 差分レビュー | `Code Review` |
| CI / PR / GitHub 操作 | `Ops` |

ルール:
- fleet は独立した subtask にのみ使う
- write-heavy task は責務分離してから委譲する
- Main は委譲と統合に集中する

---

## Copilot 固有の実行方針

- custom agents を最小構成で定義する
- hooks を使って shell や task 完了を制御する
- GitHub 連携を主力機能とする
- MCP は必要最小限に抑える

このリポジトリでは `copilot --yolo` を基準コマンドとして扱います。

---

## Git / CI / GitHub

- `main` へ直接 push しない
- PR / Issue / CI の状態を優先的に確認する
- review と要約を成果物として残す
- merge / release はユーザー確認を入れる

停止条件の例:
- 同一エラーが 3 回続く
- CI 修復が 5 回続いても改善しない
- 同じ task を繰り返している

---

## 承認ルール

自動で進めてよいもの:
- 調査
- GitHub 状態確認
- custom agents / fleet の起動
- レビュー、文書、issue 整理
- 安全な shell 実行

ユーザー確認を入れるもの:
- `push`
- `merge`
- `delete branch`
- `release`
- 破壊的変更
- 認証 / secret / 権限変更

---

## 出力順序

```text
1. 役割別ディスカッション
2. 設計決定
3. 実装
4. 検証
5. 次のアクション
```

---

## 行動原則

```text
構造化思考
可視化
委譲
継続改善
再現性
```

Copilot では、これを custom agents + fleet + GitHub integration で実現します。
