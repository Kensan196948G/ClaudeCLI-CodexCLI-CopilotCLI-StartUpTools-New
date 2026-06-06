# 16-ai-quality-gate — AI 品質ゲート統合指示

## 🎯 目的

Codex + CodeRabbit + ClaudeCode の 3 層 AI レビューを統合し、
「人間がレビュー承認のみを行う品質」を実現する。

---

## 🏗 3 層 AI レビューアーキテクチャ

```text
Layer 1: ClaudeCode     ← 実装・テスト・修復・5カテゴリ検証
Layer 2: CodeRabbit     ← 静的解析（40+ 解析器）・PR 差分レビュー
Layer 3: Codex          ← 設計・ロジック・セキュリティ深層レビュー
```

---

## ✅ マージ可能条件（全条件必須）

```text
Codex エラー: 0 件
CodeRabbit Critical/High: 0 件
テスト成功率: 100%
セキュリティ検査: PASS
パフォーマンス劣化: なし
CI: 全 job 成功
```

---

## 🔁 統合実行フロー

```text
Development 完了
 ↓
ClaudeCode: lint / test / build / security scan
 ↓
/coderabbit:review committed --base main
 ↓
/codex:review --base main --background
 ↓
指摘を統合して修正（Critical/High は必須）
 ↓
PR 作成
 ↓
CodeRabbit PR 自動レビュー
 ↓
全条件クリア → merge
```

---

## 🚨 AI 生成コード重点確認ルール

- AI 生成 SQL・正規表現・認可条件・ファイル操作は必ず security-reviewer 対象
- XSS / CSRF / IDOR / Path Traversal / SSRF を重点確認
- 同一エラー再修復は **2 回まで**。3 回目は停止して Issue 化
- AutoFix 後は必ず差分レビューを挟み、テスト通過を確認

---

## 📊 AI 役割分担

| AI | 担当領域 |
|---|---|
| ClaudeCode | 全体統制・テスト実行・デバッグ・修復 |
| CodeRabbit | 静的解析・スタイル・依存関係・secrets scan |
| Codex | アーキテクチャ・ロジック・セキュリティ設計 |
