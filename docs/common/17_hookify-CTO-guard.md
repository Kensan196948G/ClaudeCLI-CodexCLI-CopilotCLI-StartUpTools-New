# hookify による CTO 全権委任違反ガード（v3.2.2 追加）

## 目的

グローバル CLAUDE.md の **最上位原則「CTO 完全全権委任」** に違反する発話（確認・承認を求めるフレーズ）を、**ランタイムで検出して Claude に警告** する。

## 3 層防御における位置づけ

| 層 | 対策 | 効果範囲 | 実装 |
|---|---|---|---|
| 1 | template 文字列統一 | 次回セッションの起動時挙動 | `Claude/templates/claude/instructions/*.md`（v3.2.1 で完了） |
| 2 | memory 判断層 | Claude の判断ロジック | `.claude/memory/feedback_cto_startup_flow.md`（project 固有） |
| 3 | hookify ランタイム層 | **現行セッションの発話も捕捉** | 本 docs（opt-in）← **最強・本書が対応** |

1+2 は次回以降の起動時を縛るが、**現行セッション中の違反発話** は縛れない。層 3 で補完する。

## セットアップ

### 1. `.gitignore` を確認

`.gitignore` に次のいずれかが含まれていることを確認（v3.2.2 で追加済み）:

```gitignore
.claude/hookify.*.local.md
.claude/*.local.md
```

### 2. ローカル hookify ルールを配置

`.claude/hookify.warn-cto-delegation-violation.local.md` として以下を配置:

```markdown
---
name: warn-cto-delegation-violation
enabled: true
event: stop
action: warn
conditions:
  - field: transcript
    operator: regex_match
    pattern: 進めますか[？?]|以下のいずれかを選んでください|承認をお願いします|実行前に確認してください[。]|以下の手順で進めます[：:]|選択肢は\s*A\s*[/／]\s*B
---

⚠️ **CTO 全権委任違反フレーズが検出されました**

（違反時に表示する message 本文を記述）
```

完全な message 本文は `.claude/hookify.warn-cto-delegation-violation.local.md`（このリポジトリのサンプル）を参照。

### 3. 動作確認

```
/hookify:list
```

次の行が出れば登録成功:

```
| warn-cto-delegation-violation | ✅ Yes | stop | 進めますか... | hookify.warn-cto-delegation-violation.local.md |
```

## 検出フレーズ（v3.2.2 時点）

| パターン | 想定違反 |
|---|---|
| `進めますか？` | CTO 判断を求める |
| `以下のいずれかを選んでください` | 開発判断の選択肢提示 |
| `承認をお願いします` | 計画の事前承認待ち |
| `実行前に確認してください。` | 軽微な可逆操作の確認 |
| `以下の手順で進めます：` | 実行を後回しにする前置き |
| `選択肢は A / B` | 選択肢の列挙 |

## 動作方式

- **event**: `stop`（Claude がターンを終えようとするタイミング）
- **field**: `transcript`（Claude のこれまでの応答全文をスキャン）
- **action**: `warn`（発話を許容しつつ警告のみ表示）

### 厳格モード

`warn` を `block` に変更すると、違反フレーズ検出時に Claude の stop が **ブロックされる**。リリース直前や重要な自律運用中に有効。

```yaml
action: block
```

**注意**: `block` モードでは、memory / docs に違反フレーズ例を書いた場合も transcript に含まれてしまい、false positive で stop がブロックされる可能性がある。通常は `warn` を推奨。

## 安全装置（検出しないもの）

以下は CTO 全権委任の **例外** として許容される確認であり、検出対象外:

- `git push --force` を protected branch に対して
- `rm -rf` 相当の一括削除・DB DROP
- 本番デプロイ・外部サービスへの通知送信
- 認証・認可・DB スキーマ変更を伴う最終 merge
- 新規 public repository 作成
- 認証情報・API キー・シークレット変更

これらは `~/.claude/CLAUDE.md` §安全装置 6 種を参照。

## 関連

- グローバル `~/.claude/CLAUDE.md` 最上位原則
- プロジェクト `CLAUDE.md` §0 セッション開始時の自動実行
- プロジェクト `CLAUDE.md` §18 禁止事項
- hookify plugin 本体: `C:/Users/kensan/.claude/plugins/cache/claude-plugins-official/hookify/`
