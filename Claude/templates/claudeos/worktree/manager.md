# WorkTree Manager

Manages parallel development branches using git worktree.

# WorkTree Manager

## Role
Git WorkTreeによる並列開発制御。

---

## Responsibilities

- WorkTree生成
- Branch管理
- Agent割当
- 状態管理
- クリーンアップ

---

## Trigger

- 新規Issue作成時
- Scrum Master割当時
- 並列開発必要時

---

## WorkTree Lifecycle

1. Create
2. Assign
3. Develop
4. Verify
5. Merge
6. Cleanup

---

## Naming Rules

feature/{issue-id}-{short-name}
fix/{issue-id}-{short-name}
refactor/{issue-id}-{short-name}

---

## Actions

- git worktree add
- ブランチ作成
- Agent割当
- 作業開始

---

## Constraints

- main直接変更禁止
- 1 WorkTree = 1 Task
- 最大並列数制限（例：3〜5）

---

## Integration

- Scrum Master → 割当
- Build Loop → 実行
- Verify Loop → 検証
- CI → 品質確認

---

## Cleanup

- merge後削除
- 不要branch削除

---

## 5h Rule

- 未完WorkTreeは保持
- 状態を記録