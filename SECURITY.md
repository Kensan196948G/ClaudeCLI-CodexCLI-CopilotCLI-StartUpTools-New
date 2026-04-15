# Security Policy

本リポジトリのセキュリティに関するポリシー・脆弱性報告手順を定めます。

## サポート対象バージョン

| バージョン | サポート状況 |
|-----------|------------|
| v2.9.x (STABLE) | ✅ アクティブサポート |
| v3.0.0 (準備中) | ✅ リリース後に主サポート対象 |
| v2.8.x 以前 | ⚠️ セキュリティ修正のみ (6ヶ月間) |
| v2.6.x 以前 | ❌ サポート終了 |

## 脆弱性の報告

### 報告方法

**公開 Issue には投稿しないでください**。脆弱性情報が攻撃に利用される前に修正する時間を確保するため、以下のいずれかの非公開チャネルを利用してください。

1. **GitHub Private Vulnerability Reporting** (推奨)
   - 本リポジトリの [Security タブ](https://github.com/Kensan196948G/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/security) → "Report a vulnerability"
2. **リポジトリ管理者への直接連絡**
   - GitHub: [@Kensan196948G](https://github.com/Kensan196948G)

### 報告に含める情報

- 影響を受けるコンポーネント・バージョン
- 再現手順
- 想定される影響 (情報漏洩 / 権限昇格 / DoS 等)
- 可能であれば修正提案

## 対応 SLA

| 重大度 | 初回応答 | 対応方針 |
|--------|----------|----------|
| Critical (RCE / 認証バイパス / 機密情報漏洩) | 48時間以内 | 緊急パッチ + CVE 登録検討 |
| High (権限昇格 / データ破壊) | 5営業日以内 | 次期マイナーリリースに含める |
| Medium (DoS / 情報開示) | 10営業日以内 | 次期パッチリリースに含める |
| Low (軽微な設定不備 等) | 30日以内 | 計画的に対応 |

## 脆弱性の公開

- 修正版リリース後に [GitHub Security Advisories](https://github.com/Kensan196948G/ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools-New/security/advisories) で公開
- 報告者のクレジット明記 (希望者のみ)
- CVE 登録は Critical 以上を対象

## セキュリティ機能

本リポジトリでは以下のセキュリティ対策を実施しています:

| 対策 | 実装 |
|------|------|
| Secrets scan (gitleaks) | `.github/workflows/security-scan.yml` |
| 依存更新 (Dependabot) | `.github/dependabot.yml` |
| Workflow 最小権限 | 各 workflow で `permissions:` 明示 |
| PR レビュー必須 | branch protection で強制 |
| CI 必須化 | PR で test-and-validate + Secrets scan 通過を要求 |
| Codex / CodeRabbit レビュー | PR 作成時に自動実行 |

## 利用者への推奨事項

- 本ツールを実行する際は、**最小権限のアカウント**で行ってください
- secrets (API トークン等) は `.env` 等でハードコードせず、環境変数または secrets manager を利用してください
- 本リポジトリの PowerShell スクリプトは Windows ローカル環境で実行されることを前提としています。信頼できない入力 (URL・ファイル名) を与えないでください

## 関連ドキュメント

- [README.md](./README.md) — プロジェクト概要
- [CLAUDE.md](./CLAUDE.md) — 運用ポリシー
- [docs/common/14_v3リリースロードマップ.md](./docs/common/14_v3リリースロードマップ.md) — リリース計画

---

*最終更新: 2026-04-15 (v3.0.0 Phase 4 完了)*
