# Codex統合・Debug原則

## 通常レビュー

```text
/codex:review --base main --background
/codex:status
/codex:result
```

## 対抗レビュー

```text
/codex:adversarial-review --base main --background
```

## Debug / Rescue

```text
/codex:rescue --background investigate
```

## Debug原則

- 1 rescue = 1仮説
- 最小修正
- 深追い禁止
- 同一原因 3 回まで
- 原因不明時は推測修正を禁止
