# Pipeline Rules

Rules for CI execution and stability.

# Pipeline Rules

## Role
CIパイプラインの実行ルール定義。

---

## Execution Rules

- Build必須
- Test必須
- Lint必須
- Security Scan必須

---

## Failure Policy

- 1回失敗 → 修正
- 2回失敗 → 原因分析強化
- 3回失敗 → Block候補

---

## STABLE連携

STABLE条件：

- CI success
- Test success
- Error 0
- Security issue 0

---

## Deploy Gate

以下でのみ許可：

- STABLE達成
- CI安定
- Review完了

---

## Loop Guard連携（重要）

- 無限ループ検知で停止
- retry上限で停止
- Blockedへ移行

---

## 5h Rule

- 5時間到達でCI停止
- 未完でも状態保存