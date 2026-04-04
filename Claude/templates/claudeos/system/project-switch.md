# Project Switch Engine

## Role
セッション開始時に作業対象プロジェクトを動的に選択・切替する。
プロジェクトリストはGitHubから毎回取得し、固定テーブルは持たない。

---

## Projects Discovery（毎回実行）

### Step 1: アクティブリポジトリを動的取得
```bash
# 自分のリポジトリを全取得（archived除外）
gh repo list Kensan196948G \
  --no-archived \
  --limit 50 \
  --json name,updatedAt,isPrivate \
  --jq '.[] | select(.name != null)'
```

### Step 2: 除外リストを適用
以下に該当するリポジトリはスコアリング対象から除外する。

除外条件ファイル: `.loop-project-exclude.md`
```
# 除外リポジトリ（移植完了・廃止・一時停止）
ServiceMatrix
Backup-management-system
```

除外ファイルが存在しない場合は全リポジトリを対象とする。

### Step 3: スコアリングして選択
取得したリポジトリ一覧に対してスコアリングを実行する。

---

## Selection Logic（優先順位順）

### 優先度1: 手動上書き
`.loop-project-override.md` が存在し expires 未来日 → 指定プロジェクトを使用

### 優先度2: 前回継続
前回 STABLE 未達 かつ残課題あり → 同プロジェクト継続

### 優先度3: 自動スコアリング
| 指標 | スコア |
|---|---|
| Blocked Issue あり | +5 |
| CI failure | +3 |
| Open Issue 5件以上 | +2 |
| Open Issue 1件以上 | +1 |
| 最終更新 24時間以内 | +2 |
| 最終更新 7日以内 | +1 |

---

## Error Handling
- gh 認証エラー → 停止・GITHUB_TOKEN確認を促す
- リポジトリ0件 → Blocked で停止・Issue起票
- 全スコア同点 → 最終更新日が最も新しいものを選択
```

---

## 運用フロー図
```
起動
 ↓
gh repo list で動的取得
 ↓
.loop-project-exclude.md で除外フィルタ
 ↓
.loop-project-override.md チェック（手動上書きあり？）
 ↓ なし
スコアリング → 最高値を選択
 ↓
.loop-project-context.md に書き出し
 ↓
Orchestrator へ通知