# Progressive Disclosure — スキル遅延読み込みプロトコル

セッション開始時に全スキル全文をロードする代わりに、
必要性が確定したスキルのみ全文取得する「段階的開示」を実装する。

本ファイルは **呼び出された Claude への命令書** である。
スキルを利用する前に以下のプロトコルに従うこと。

---

## 位置づけ

| 項目 | 値 |
|---|---|
| 対象 | `.claude/claudeos/skills/**/*.md` (64 スキル) |
| 制御フィールド | `state.json.session.context_load_tier` |
| 参照元 Issue | #106 |
| 参考 | Anthropic blog — Harnessing Claude's Intelligence, Pattern 1 "Use what Claude knows" |

---

## 二層スキル構造 — 本プロトコル vs Claude Code ネイティブ skill

ClaudeOS には **2 種類の skill 層**があり、ロード機構が異なる。混同しないこと。

| 層 | パス | ロード機構 |
|---|---|---|
| **① ClaudeOS カーネル skill** | `.claude/claudeos/skills/<name>/SKILL.md` | **本プロトコル**（フロントマター索引 → tier 別 on-demand）。入れ子パスのため Claude Code ネイティブ discovery 対象外 |
| **② Claude Code ネイティブ skill** | `.claude/skills/<name>/SKILL.md` | **Claude Code 公式 discovery**（description で auto-trigger・`/skills` 表示） |

### 配布時の挙動（重要 — repo により異なる）

| 対象 | native `.claude/skills/`（②） | 意図 |
|---|---|---|
| **本 repo（SOT/ツール）** | 運用 skill のみ（`cto-session-start` / `webui-health-check` の 2 件） | 66 件は**配布用ライブラリ**で大半がこの repo に無関係なドメイン。自身では native 化せず kernel path（①）に置き本プロトコルで索引する |
| **登録（downstream）プロジェクト** | **66 件すべて** | `TemplateSyncManager` E-3（v3.2.51）が `Claude/templates/claudeos/skills/` → `.claude/skills/` を同期。downstream では 66 を native discovery で使う。**frontmatter の `description` が auto-trigger を駆動**するため、SOT 更新後は E-3 再同期で配布する |

> ⚠️ 以前ここには「① を ② へ一括 mirror しない（トークン肥大回避）」と記載していたが、これは**本 repo 限定の方針**であり、登録プロジェクトでは E-3 が native 66 を配布するのが正（2026-06-06 訂正）。「mirror しない」は globally な禁則ではない。
>
> 💡 Claude Code の native discovery は **body を遅延ロード**（起動時は name+description のみ取得）するため、本プロトコルの主目的（body 遅延ロード）と機能的に重複する。本プロトコルは本 repo の kernel-path skill の索引用として残置している。

### ② の構造要件

- ② は **必ず `.claude/skills/<name>/SKILL.md`**（サブディレクトリ + `SKILL.md`）構造にすること。フラットな `.claude/skills/foo.md` は discovery されない（2026-06-06 に `cto-session-start` / `webui-health-check` で発生していた構造バグを修正済み）。
- frontmatter の `description` は **① の索引でも ② の auto-trigger でも読まれる**共通の高シグナル項目。両層とも description を整備する価値がある（`docs/agents-skills-inventory-2026Q2.md` で 36/64 が削除候補に分類されている点も合わせて棚卸しの対象）。

---

## Tier 定義

| Tier | ロード範囲 | 適用場面 | トークン節約 |
|---|---|---|---|
| `minimal` | フロントマターのみ（先頭 20 行） | Light タスク（1 ファイル修正・ドキュメント更新） | 最大 ~70% |
| `standard` | フロントマター + H1/H2 見出し構造 | Full タスク（機能追加・バグ修正）**既定** | ~30-50% |
| `full` | 全文ロード（従来の挙動） | 特定スキルが深く必要と判定された場合のみ | 節約なし |

既定は `standard`。state.json が存在しない場合も `standard` とする。

---

## 読み取りプロトコル

### Step 1: state.json から tier を取得

```
Read("./state.json")  # session.context_load_tier を確認
```

state.json 不在 → `standard` を使用する。

### Step 2: tier に応じた読み込み

#### minimal

```python
Read(".claude/claudeos/skills/{name}/SKILL.md", limit=20)
# フロントマター（---から---まで）と最初の ## 見出しのみ取得
```

#### standard（既定）

```python
Read(".claude/claudeos/skills/{name}/SKILL.md", limit=40)
# フロントマター + H1/H2 見出しが概ね 40 行以内に収まる設計
```

#### full

```python
Read(".claude/claudeos/skills/{name}/SKILL.md")
# 制限なし全文取得
```

### Step 3: 必要なら full に昇格

`standard` で読んだ後、以下のいずれかに該当する場合のみ full 再読み込みを行う:

- スキルの H2 見出しから「このスキルが深く関係する」と判断した場合
- ユーザーが明示的にスキルの詳細手順を要求した場合
- セキュリティ・認証・DB 変更タスクで対応スキルが必要な場合

昇格は **1 スキルずつ、必要が確定してから** 行う。
「念のため」で full にしない。

---

## タスク規模による自動 tier 選択

セッション開始時、Claude はタスク規模を判定して tier を選択し、
`state.json.session.context_load_tier` を更新する。

| 判定基準 | Tier |
|---|---|
| 変更対象ファイル数 ≤ 2、かつ差分 < 50 行 | `minimal` |
| 上記以外（機能追加・バグ修正・複数ファイル変更） | `standard` ← **既定** |
| セキュリティ / 認証 / DB スキーマ変更 | `standard`（対象スキルのみ `full` 昇格） |

tier を変更する場合は以下のように state.json を更新する:

```json
{ "session": { "context_load_tier": "minimal" } }
```

---

## 全スキル一覧プリロード（session 開始時）

セッション開始時は全スキルのフロントマター（`limit=20`）をプリロードし、
インデックスとしてメモリに保持する。全文は呼び出し時まで取得しない。

```python
# セッション開始時に実行（tier に関わらず必須）
for skill_path in Glob(".claude/claudeos/skills/**/*.md"):
    Read(skill_path, limit=20)  # フロントマター（description）のみ
```

これにより「どのスキルが存在するか」は常に把握しつつ、
全文のトークンコストは必要時まで発生させない。

---

## state.json スキーマ（本プロトコルが参照するブロック）

```json
{
  "session": {
    "context_load_tier": "standard",
    "_comment": "minimal=フロントマターのみ / standard=H1/H2見出し構造 / full=全文"
  }
}
```

---

## 期待効果

| 状況 | 従来（full） | minimal | standard |
|---|---|---|---|
| 64 スキル × 平均 200 行 | ~12,800 行 | ~1,280 行 | ~2,560 行 |
| 推定トークン消費 | ~100% | ~10% | ~20% |

セッション開始コストの 80-90% 削減（minimal 時）が見込まれる。

---

## 参考

- Issue #106（本プロトコルの実装対象）
- Anthropic blog: [Harnessing Claude's Intelligence](https://claude.com/blog/harnessing-claudes-intelligence) Pattern 1
- `.claude/claudeos/skills/` — 対象スキル群（64 スキル）
- `state.json` — tier 制御フィールドの格納先
