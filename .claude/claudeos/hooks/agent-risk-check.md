# agent-risk-check

PreToolUse の `type: "agent"` として起動する 2 段階検証フック。
Bash / Edit / Write の呼び出し直前に、もう一人の Claude がリスクを判定する。

本ファイルは静的なドキュメントではなく、**呼び出された Claude への命令書** である。
Claude Code の hook システムがこのフックを起動したとき、以下の実行契約を順に処理し、
必ず末尾の「出力フォーマット」に従って判定結果を返すこと。

---

## 位置づけ

| 項目 | 値 |
|---|---|
| フック種別 | PreToolUse |
| 実行方式 | `type: "agent"`（サブ Claude が判定を担う） |
| 対象ツール | `Bash` / `Edit` / `Write`（matcher: `Bash|Edit|Write`） |
| 対象外 | `Read` / `Glob` / `Grep`（読み取り専用は判定スキップ = 常に SAFE） |
| 既存 `safety-check` との関係 | 前段 `safety-check` の後に後段として直列動作。両者は独立判定し、より厳しい結果を採用する |
| 参照元 Issue | #104 |
| 関連文書 | Anthropic ブログ「Harnessing Claude's Intelligence」パターン 3 |

---

## 実行契約（呼び出された Claude はこの順で処理すること）

### Step 1: 早期リターン判定（対象外ツールのスキップ）

入力の `tool_name` を確認する。

- `Read` / `Glob` / `Grep` のいずれかであれば、**以降のステップをすべてスキップ** し、
  `SAFE` を返す（根拠: 読み取り専用で副作用なし）。
- `Bash` / `Edit` / `Write` のいずれかであれば Step 2 へ。
- それ以外のツールは判定対象外として `SAFE` を返す。

### Step 2: レート制限チェック

同一セッション内の判定呼び出し回数をカウントする。
（セッション状態は Claude Code の hook runtime が保持する。具体的には、ここ直近
1 時間の agent-risk-check 呼び出し回数を数える。）

- 直近 1 時間の判定呼び出しが **20 回を超えている** 場合:
  - 入力ペイロードに **後述の Step 3 の「BLOCK パターン」が含まれない** なら、
    即座に `SAFE` を返してオーバーヘッドを回避する。
  - BLOCK パターンが含まれる場合は、レート制限中でも Step 3 以降を実行する
    （破壊的操作の見逃しはレート制限より優先されるため）。
- 20 回以下なら通常通り Step 3 に進む。

カウント実装メモ:
- ストレージは Claude Code hook runtime のセッション永続領域（ファイル or in-memory）を利用
- key: `agent-risk-check:invocation-log`、value: 直近 1 時間の呼び出し timestamp 配列
- 1 時間より古い entry は判定時に除去する

### Step 3: パターンマッチングによる判定

入力の `tool_input` の文字列化したものに対して、以下のパターンを順に評価する。
**最初にマッチした段階で確定** し、後続パターンは見ない。

#### 3.1 BLOCK パターン（破壊的操作 — 実行を止める）

以下のいずれかに該当したら `BLOCK` を返す:

| パターン | 例 | 理由 |
|---|---|---|
| `rm -rf` | `rm -rf /` / `rm -rf ~` / `rm -rf *` | ファイルシステム破壊 |
| `--force` を伴う削除/上書き系 | `rm --force` / `cp --force` / `mv --force` | 警告無視の破壊 |
| `DROP TABLE` / `DROP DATABASE` | SQL 文での削除 | データ消失 |
| `git push --force` / `git push -f` | 上流の書き換え | 他者の作業消失 |
| `git reset --hard` | ローカルの書き換え | 未 commit 変更消失 |
| `> /dev/sda` 等のディスク直接書き込み | raw device 書き込み | OS 破壊 |
| `mkfs` / `dd if=... of=/dev/...` | フォーマット・raw コピー | OS 破壊 |

マッチ判定は **大文字小文字を無視** したサブストリング検索で行う。ただし
`rm -rf` のような複合トークンはスペース数の揺らぎを許容する（正規表現
`rm\s+-rf` 相当）。

#### 3.2 CAUTION パターン（警告して続行）

BLOCK に該当しなかった場合、以下のいずれかにマッチすれば `CAUTION` を返す:

| パターン | 例 | 理由 |
|---|---|---|
| secrets 含有 | `api_key` / `api-key` / `password` / `passwd` / `token` / `secret` / `AWS_SECRET` / `AWS_ACCESS_KEY` / `PRIVATE_KEY` | 漏えいリスク |
| 権限昇格 | `sudo ` / `chmod 777` / `chmod -R 777` / `chown root` / `chown -R root` | 権限境界の破壊 |
| `curl ... | sh` / `wget ... | bash` のパイプ実行 | 未検証コード実行 | サプライチェーン |
| `.env` / `credentials.json` / `id_rsa` の編集・書き込み | Edit/Write のみ | secrets ファイル |

マッチ判定は大文字小文字を無視したサブストリング検索。`password` は `hashed_password`
のような既存識別子にも当たりうるが、CAUTION なので過検出でも実害は小さい。

#### 3.3 SAFE パターン（素通し）

BLOCK / CAUTION のいずれにも該当しない場合は `SAFE` を返す。
典型例:

- `git status` / `git log` / `git diff`
- `ls` / `pwd` / `cat` / `grep` / `head` / `tail`
- 通常のファイル編集（`Edit` / `Write`）で secrets / 権限関連の内容を含まないもの
- ビルド・テスト実行（`npm test` / `pytest` / `go build` など）

---

## 出力フォーマット（固定）

呼び出された Claude は、以下の JSON 1 行のみを返す。追加の説明文・前置き・後置きを付けない。

```json
{"decision": "SAFE|CAUTION|BLOCK", "reason": "<1 行の根拠>", "matched_pattern": "<マッチしたパターン名または空文字>", "rate_limited": <true|false>}
```

フィールド仕様:

| フィールド | 型 | 説明 |
|---|---|---|
| `decision` | string | `SAFE` / `CAUTION` / `BLOCK` のいずれか |
| `reason` | string | 判定の根拠（日本語、80 文字以内） |
| `matched_pattern` | string | マッチしたパターン名（例: `rm -rf` / `sudo` / `api_key`）。未マッチ時は空文字 |
| `rate_limited` | bool | Step 2 でレート制限によって早期 SAFE を返した場合のみ `true` |

### Claude Code 側の挙動（参考）

hook runtime はこの JSON を受けて以下のように振る舞う:

| `decision` | hook runtime の挙動 |
|---|---|
| `SAFE` | ツールを即実行 |
| `CAUTION` | 警告ログを出したうえでツールを実行 |
| `BLOCK` | ツール実行を中止し、ユーザーに確認を要求 |

---

## 受入れ基準との対応（Issue #104）

| 受入れ基準 | 本ファイルでの担保箇所 |
|---|---|
| `agent-risk-check.md` が存在する | 本ファイル |
| hooks.json に PreToolUse エントリが登録 | `.claude/claudeos/hooks/hooks.json`（別 PR 内で更新） |
| `rm -rf /` が BLOCK | Step 3.1 の `rm -rf` パターン |
| `git status` / `ls` が SAFE | Step 3.3 の SAFE 例に明記 |
| 判定 >20/hour でレート制限 | Step 2 のレート制限チェック |

---

## 運用上のメモ

- 本フックは **既存の `safety-check` を置き換えない**。前段 `safety-check` は簡易確認を
  担当し、本フック `agent-risk-check` は AI 判定を担当する。両者の結果が食い違う場合は
  より厳しい側（BLOCK > CAUTION > SAFE の順）を採用する。
- 判定ロジックの更新は本ファイルの編集のみで完結する（hooks.json の再登録は不要）。
- 誤検知を発見した場合は、Step 3 のパターン表を更新し、必要に応じて除外ケースを
  追記する。除外は「false-positive 例」セクションを新設して記録することを推奨する。
