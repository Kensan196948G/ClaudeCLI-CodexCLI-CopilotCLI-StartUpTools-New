# 10-security-testing — セキュリティ テスト検証・デバッグ指示

## 🎯 目的

OWASP Top10 を基準にセキュリティ全領域を検査し、Critical/High 脆弱性ゼロを維持する。

---

## 🔐 認証・認可検証

1. MFA
2. JWT
3. Session
4. RBAC
5. Admin 権限
6. Password Policy
7. Token 期限
8. Logout

---

## 🛡 脆弱性検証（OWASP Top10 必須）

1. SQL Injection
2. XSS
3. CSRF
4. SSRF
5. Directory Traversal
6. Command Injection
7. File Upload 攻撃
8. Clickjacking
9. Open Redirect
10. XXE

---

## 🌐 通信セキュリティ

1. HTTPS 強制
2. TLS 確認
3. HSTS
4. Secure Cookie
5. CSP Header
6. CORS 制御

---

## 📜 ログ・監査

1. 監査ログ
2. 改ざん耐性
3. マスキング
4. SIEM 連携
5. 異常検知

---

## 🐞 セキュリティデバッグツール

```bash
OWASP ZAP / BurpSuite
npm audit / pip-audit
Dependabot
SAST / DAST
CVE Scan
```

---

## 🚨 AI 生成コード重点確認

- AI 生成 SQL・正規表現・認可条件・ファイル操作は必ず security-reviewer 対象とする
- XSS / CSRF / IDOR / Path Traversal / SSRF は AI 生成コードで特に重点確認

---

## 🚫 禁止事項

- Critical/High 未解消のまま merge
- セキュリティ例外の無断承認
- Secret のハードコード
