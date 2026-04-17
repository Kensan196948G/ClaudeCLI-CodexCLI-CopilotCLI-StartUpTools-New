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
    pattern: (?:^|[\n。．:：])\s*(?:実行してよろしいですか[？?]|以下のいずれか(?:を選んでください|から選択してください)|(?:ご)?承認をお願いします[。]?|実行前に確認してください[。]?|この方針で進めて問題ないですか[？?]|どの方針(?:で進めますか|にしますか)[？?]|別プラン[:：]\s*\(a\)|ユーザーに確認します[:：])
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

## 検出フレーズ（v3.2.3 時点）

false positive 低減のため、**distinctive（他の文脈で出にくい）** フレーズに限定:

| パターン | 想定違反 | 追加 |
|---|---|---|
| `実行してよろしいですか？` | 可逆操作に対する不要な実行確認 | v3.2.2 |
| `以下のいずれかを選んでください` / `以下のいずれかから選択してください` | 開発判断の選択肢提示 | v3.2.2 |
| `承認をお願いします。` / `ご承認をお願いします` | 計画の事前承認待ち | v3.2.2 |
| `実行前に確認してください。` | 軽微な可逆操作の確認 | v3.2.2 |
| `この方針で進めて問題ないですか？` | 既決方針への再承認要求 | **v3.2.3** |
| `どの方針で進めますか？` / `どの方針にしますか？` | 複数プランからの選択要求 | **v3.2.3** |
| `別プラン: (a)` | 選択肢列挙の典型形 (`(a)/(b)/(c)` パターン) | **v3.2.3** |
| `ユーザーに確認します:` / `ユーザーに確認します：` | 確認待ちの明示的宣言 | **v3.2.3** |

### 意図的に**除外**したフレーズ（false positive 回避）

| 除外フレーズ | 理由 |
|---|---|
| `進めますか？` | 一般会話でも頻出（例: 「次のステップに進めますか？」は要件確認の妥当な問い合わせ） |
| `選択肢は A / B / C` | docs / CHANGELOG / コメントで例示として頻出 |
| `以下の手順で進めます：` | 計画説明の正当な導入表現にもなる |

これらを検出したい場合は、より文脈を絞った正規表現（例: 末尾句点 + 行末アンカー）への強化が必要。現状は **精度優先で除外**。

### v3.2.3 で追加した 4 パターンの正当性

| パターン | distinctive な理由 |
|---|---|
| `この方針で進めて問題ないですか？` | `方針で進めて問題ないですか` という逐語連結は自然会話や docs 例示でほぼ出現しない |
| `どの方針で進めますか？` / `どの方針にしますか？` | `どの方針` を含む疑問文は CTO 判断の投げ返しに特有 |
| `別プラン: (a)` | `別プラン` + `(a)` の組み合わせ (`A/` ではなく小文字括弧) は選択肢列挙の典型で、設計 docs の例示と区別しやすい |
| `ユーザーに確認します:` | `確認します:` 型の明示宣言は CTO 判断抑止 (= 自律実行停止) を意味する自己文言に限られる |

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
