# Branch Policy

Defines branching rules for feature development.

# Branch Policy

## Role
安全な開発ブランチルール。

---

## Rules

- main直接push禁止
- PR経由のみmerge
- CI成功必須

---

## Branch Types

- feature/*
- fix/*
- refactor/*
- hotfix/*
- chore/*

---

## Naming

{type}/{issue-id}-{short-desc}

例：
feature/123-user-login
fix/456-api-error

---

## Commit Rules

- 小さく頻繁にcommit
- 意味のあるメッセージ

---

## Merge Rules

- CI success必須
- review必須
- squash or rebase

---

## Protection

- main branch保護
- force push禁止

---

## Integration

- WorkTree Managerと連携
- GitHub PRと連動