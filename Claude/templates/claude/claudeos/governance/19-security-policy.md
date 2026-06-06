# 19-security-policy — セキュリティポリシー

## 🎯 目的

ClaudeOS 全セッションで Security First を徹底し、脆弱性ゼロを維持する。

---

## 🔐 Security First 原則

- Security Critical 検出 → **即時対応（最優先）**
- Agent Teams パターン B を自動発動
- 未解消 Critical/High は merge 禁止

---

## 🛡 必須確認項目

| カテゴリ | 確認内容 |
|---|---|
| Secrets | .env 漏洩 / API キーハードコード / トークン露出 |
| 認証・認可 | JWT 検証 / RBAC / 権限昇格 / IDOR |
| 入力検証 | XSS / SQLi / Command Injection / Path Traversal |
| 通信 | HTTPS 強制 / TLS バージョン / HSTS / Secure Cookie |
| 依存関係 | npm audit / CVE Scan / Dependabot アラート |

---

## 🔁 Security Agent 起動タイミング

- Verify フェーズ: security-reviewer 必須参加
- PR 作成前: secrets scan 必須
- Release 前: 最終セキュリティスキャン

---

## 🚫 禁止事項（セキュリティ関連）

- secrets のコミット
- HTTP での認証情報送信
- 権限チェックなしの API エンドポイント
- セキュリティ例外の無断承認
- force push による審査回避
