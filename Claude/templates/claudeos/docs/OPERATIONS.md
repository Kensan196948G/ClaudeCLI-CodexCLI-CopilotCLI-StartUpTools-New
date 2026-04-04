# 運用ガイド

## 1. 基本思想

- 調査してから実装する
- 小さく変更して大きく壊さない
- 変更後は必ず検証する
- README と文書も成果物として扱う
- 同じ失敗を繰り返す前に止まる

## 2. 推奨ループ

1. `search-first`
2. `/plan`
3. skill 適用
4. 実装またはレビュー
5. `/verify`
6. `/update-docs`
7. `/learn` または `/learn-eval`

## 3. 代表的な運用パターン

### 新規機能追加

- `search-first`
- `backend-patterns` または `frontend-patterns`
- `tdd-workflow`
- `/verify`

### バグ修正

- `search-first`
- `verification-loop`
- `security-review` 必要時
- `/verify`

### 設計見直し

- `planner`
- `architect`
- `api-design` や `database-migrations`
- `/update-docs`

## 4. agent の使いどころ

- `planner`: 作業分解が必要なとき
- `architect`: 境界や責務を見直すとき
- `code-reviewer`: 差分の品質確認
- `security-reviewer`: 認証や入力検証が絡むとき
- `loop-operator`: 長い自律ループを整理したいとき

## 5. 停止条件

- 同じ失敗を 3 回以上繰り返している
- 外部依存が原因で先へ進めない
- 破壊的変更の影響が読めない
- セキュリティ上の懸念が解消していない

## 6. 再開時に残すもの

- 何をやったか
- どこまで通ったか
- 何が詰まっているか
- 次にやる一手

## 7. ドキュメント更新方針

- 利用者に影響する機能変更があれば README を更新する
- セットアップ手順が変わったら導入手順書を更新する
- 運用フローが変わったらこの文書を更新する
