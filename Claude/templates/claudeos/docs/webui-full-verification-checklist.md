---
title: WebUI フルスタック検証チェックリスト
version: v1.0.0
updated: 2026-04-30
scope: WebUI案件（フロントエンド＋バックエンド）
---

# WebUI フルスタック検証チェックリスト

## 凡例

| 列 | 値 | 意味 |
|---|---|---|
| **必須度** | 必須 | マージ・リリースブロック |
| | 条件 | skip_if 条件が真の場合はスキップ可 |
| | 任意 | 時間・Token 残量に応じて実施 |
| **実行方法** | 自動 | CI/CD で完全自動 |
| | 半自動 | 自動実行後に結果を目視確認 |
| | 目視 | 人間が手動で確認 |
| **タイミング** | PR | PR 作成時（Gate-1/2） |
| | merge | main merge 直前 |
| | nightly | 夜間 CI バッチ |
| | release | リリース前 Staging（Gate-3） |
| | incident | 障害発生時 |

## サマリー（自動集計用）

| 区分 | 件数 |
|---|---|
| 必須 | 118 |
| 条件付き | 115 |
| 任意 | 17 |
| **計** | **250** |

| タイミング | 件数 |
|---|---|
| PR | 138 |
| nightly | 52 |
| release | 48 |
| merge | 8 |
| incident | 4 |

---

## 1. 画面表示テスト（UI Rendering）

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 1 | 全画面が正常表示される | 必須 | 半自動 | DevUI | PR | Playwright screenshot | — |
| 2 | CSS崩れがない | 必須 | 自動 | DevUI | PR | screenshot diff | — |
| 3 | フォント崩れがない | 条件 | 目視 | DevUI | release | screenshot | — |
| 4 | アイコン表示正常 | 条件 | 半自動 | DevUI | PR | screenshot | — |
| 5 | ダークモード対応確認 | 条件 | 半自動 | DevUI | release | screenshot | no_dark_mode |
| 6 | 解像度変更時の崩れ確認 | 条件 | 半自動 | DevUI | release | screenshot | — |
| 7 | ブラウザズーム対応 | 任意 | 目視 | DevUI | release | — | — |
| 8 | 125%/150% DPI対応 | 条件 | 目視 | DevUI | release | — | desktop_only |
| 9 | スクロール表示確認 | 必須 | 半自動 | DevUI | PR | screenshot | — |
| 10 | モーダル表示正常 | 条件 | 自動 | DevUI | PR | screenshot | no_modal |
| 11 | ツールチップ表示正常 | 条件 | 半自動 | DevUI | PR | screenshot | no_tooltip |
| 12 | テーブル列崩れ確認 | 条件 | 半自動 | DevUI | PR | screenshot | no_table |
| 13 | サイドメニュー開閉確認 | 条件 | 自動 | DevUI | PR | Playwright log | no_sidebar |
| 14 | アコーディオン動作確認 | 条件 | 自動 | DevUI | PR | Playwright log | no_accordion |
| 15 | ローディングUI表示確認 | 必須 | 自動 | DevUI | PR | screenshot | — |
| 16 | 404画面表示確認 | 必須 | 自動 | QA | PR | Playwright log | — |
| 17 | 500エラー画面確認 | 必須 | 自動 | QA | PR | Playwright log | — |
| 18 | 長文表示確認 | 条件 | 半自動 | DevUI | release | screenshot | — |
| 19 | 日本語表示崩れ確認 | 必須 | 半自動 | DevUI | PR | screenshot | no_japanese |
| 20 | Unicode/絵文字表示確認 | 条件 | 半自動 | DevUI | release | screenshot | — |

---

## 2. レスポンシブ・端末対応

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 21 | Windows Edge確認 | 必須 | 半自動 | DevUI | PR | screenshot | — |
| 22 | Chrome確認 | 必須 | 自動 | Tester | PR | CI URL | — |
| 23 | Firefox確認 | 条件 | 半自動 | DevUI | nightly | screenshot | no_firefox_support |
| 24 | iPad表示確認 | 条件 | 目視 | DevUI | release | screenshot | no_tablet_support |
| 25 | Android表示確認 | 条件 | 目視 | DevUI | release | screenshot | no_mobile_support |
| 26 | 画面回転対応 | 条件 | 目視 | DevUI | release | — | no_mobile_support |
| 27 | タッチ操作確認 | 条件 | 半自動 | DevUI | release | Playwright log | no_mobile_support |
| 28 | キーボード操作確認 | 必須 | 半自動 | QA | PR | Playwright log | — |
| 29 | タブ移動確認 | 必須 | 半自動 | QA | PR | Playwright log | — |
| 30 | モバイルメニュー確認 | 条件 | 半自動 | DevUI | release | screenshot | no_mobile_support |

---

## 3. JavaScript動作確認

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 31 | JSエラー有無 | 必須 | 自動 | Tester | PR | console error log | — |
| 32 | Console Error確認 | 必須 | 自動 | Tester | PR | console error log | — |
| 33 | Promise失敗時処理 | 必須 | 自動 | QA | PR | test log | — |
| 34 | 非同期通信成功確認 | 必須 | 自動 | Tester | PR | network log | — |
| 35 | 非同期通信失敗確認 | 必須 | 自動 | QA | PR | network log | — |
| 36 | APIタイムアウト確認 | 必須 | 自動 | QA | PR | test log | — |
| 37 | ボタン連打確認 | 必須 | 自動 | QA | PR | Playwright log | — |
| 38 | 二重送信防止 | 必須 | 自動 | QA | PR | test log | — |
| 39 | イベント重複発火確認 | 必須 | 自動 | QA | PR | test log | — |
| 40 | localStorage動作 | 条件 | 自動 | DevUI | PR | test log | no_localstorage |
| 41 | sessionStorage動作 | 条件 | 自動 | DevUI | PR | test log | no_sessionstorage |
| 42 | Cookie保存確認 | 条件 | 自動 | Security | PR | test log | no_cookie |
| 43 | ブラウザ戻る対応 | 条件 | 半自動 | DevUI | PR | Playwright log | no_SPA |
| 44 | 画面リロード確認 | 必須 | 半自動 | QA | PR | Playwright log | — |
| 45 | SPAルーティング確認 | 条件 | 自動 | DevUI | PR | test log | no_SPA |
| 46 | キャッシュ更新確認 | 条件 | 半自動 | Ops | nightly | test log | — |
| 47 | ServiceWorker確認 | 条件 | 自動 | DevUI | PR | test log | no_PWA |
| 48 | WebSocket確認 | 条件 | 自動 | DevAPI | PR | test log | no_websocket |
| 49 | リアルタイム更新確認 | 条件 | 半自動 | DevUI | PR | test log | no_realtime |
| 50 | JSメモリリーク確認 | 条件 | 半自動 | QA | nightly | memory profile | — |

---

## 4. 入力フォーム検証

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 51 | 必須チェック | 必須 | 自動 | QA | PR | test log | — |
| 52 | 空文字確認 | 必須 | 自動 | QA | PR | test log | — |
| 53 | NULL送信確認 | 必須 | 自動 | QA | PR | test log | — |
| 54 | 数値入力制限 | 条件 | 自動 | QA | PR | test log | no_numeric_input |
| 55 | 文字数制限 | 条件 | 自動 | QA | PR | test log | no_length_limit |
| 56 | 禁止文字確認 | 条件 | 自動 | QA | PR | test log | — |
| 57 | メール形式確認 | 条件 | 自動 | QA | PR | test log | no_email_input |
| 58 | 電話番号形式確認 | 条件 | 自動 | QA | PR | test log | no_phone_input |
| 59 | 日付形式確認 | 条件 | 自動 | QA | PR | test log | no_date_input |
| 60 | CSVアップロード確認 | 条件 | 半自動 | QA | PR | test log | no_csv_upload |
| 61 | ファイルサイズ制限 | 条件 | 自動 | QA | PR | test log | no_file_upload |
| 62 | 拡張子制限 | 条件 | 自動 | Security | PR | test log | no_file_upload |
| 63 | ドラッグ＆ドロップ確認 | 条件 | 半自動 | DevUI | PR | Playwright log | no_DnD |
| 64 | 日本語IME入力確認 | 必須 | 目視 | QA | release | screenshot | no_japanese |
| 65 | Enter送信誤動作確認 | 必須 | 自動 | QA | PR | Playwright log | — |
| 66 | バリデーション表示確認 | 必須 | 自動 | DevUI | PR | screenshot | — |
| 67 | リアルタイム検証確認 | 条件 | 自動 | QA | PR | test log | no_realtime_validation |
| 68 | エラーメッセージ確認 | 必須 | 自動 | QA | PR | screenshot | — |
| 69 | 入力復元確認 | 条件 | 半自動 | DevUI | PR | test log | no_auto_save |
| 70 | 多重Submit確認 | 必須 | 自動 | QA | PR | test log | — |

---

## 5. フロントエンドセキュリティ

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 71 | XSS対策確認 | 必須 | 自動 | Security | PR | SAST log | — |
| 72 | CSRF対策確認 | 必須 | 自動 | Security | PR | test log | — |
| 73 | CSP確認 | 必須 | 自動 | Security | PR | security header log | — |
| 74 | Cookie Secure確認 | 必須 | 自動 | Security | PR | test log | — |
| 75 | HttpOnly確認 | 必須 | 自動 | Security | PR | test log | — |
| 76 | Token漏洩確認 | 必須 | 自動 | Security | PR | secret scan log | — |
| 77 | JWT保存方法確認 | 必須 | 半自動 | Security | PR | Security review | no_JWT |
| 78 | URL直打ち確認 | 必須 | 自動 | QA | PR | Playwright log | — |
| 79 | 権限外画面遷移確認 | 必須 | 自動 | Security | PR | test log | — |
| 80 | DevTools改ざん確認 | 条件 | 目視 | Security | release | — | — |
| 81 | HTML改ざん確認 | 条件 | 目視 | Security | release | — | — |
| 82 | JS難読化確認 | 条件 | 半自動 | Security | release | bundle check | no_obfuscation |
| 83 | 秘密情報埋め込み確認 | 必須 | 自動 | Security | PR | secret scan log | — |
| 84 | APIキー露出確認 | 必須 | 自動 | Security | PR | secret scan log | — |
| 85 | HTTPS強制確認 | 必須 | 自動 | Security | PR | test log | — |

---

## 6. フロントエンド性能試験

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 86 | 初回表示速度 | 条件 | 自動 | QA | nightly | Lighthouse JSON | — |
| 87 | API応答速度 | 必須 | 自動 | QA | PR | performance log | — |
| 88 | 画像読込速度 | 条件 | 自動 | QA | nightly | Lighthouse JSON | no_images |
| 89 | JS読込速度 | 条件 | 自動 | CIManager | nightly | Lighthouse JSON | — |
| 90 | CSS最適化確認 | 条件 | 自動 | DevUI | nightly | bundle size log | — |
| 91 | LazyLoad確認 | 条件 | 半自動 | DevUI | PR | Playwright log | no_lazy_load |
| 92 | Bundleサイズ確認 | 必須 | 自動 | CIManager | PR | bundle size log | — |
| 93 | Lighthouse確認 | 条件 | 自動 | QA | nightly | Lighthouse JSON | — |
| 94 | FCP確認 | 条件 | 自動 | QA | nightly | Lighthouse JSON | — |
| 95 | LCP確認 | 条件 | 自動 | QA | nightly | Lighthouse JSON | — |
| 96 | CLS確認 | 条件 | 自動 | QA | nightly | Lighthouse JSON | — |
| 97 | FPS確認 | 条件 | 半自動 | QA | nightly | performance profile | — |
| 98 | CPU使用率確認 | 条件 | 半自動 | QA | nightly | performance profile | — |
| 99 | メモリ使用量確認 | 条件 | 半自動 | QA | nightly | memory profile | — |
| 100 | 長時間稼働確認 | 条件 | 半自動 | QA | nightly | Soak test log | — |

---

## 7. UX・運用系確認

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 101 | 操作直感性確認 | 任意 | 目視 | DevUI | release | — | — |
| 102 | エラー時誘導確認 | 必須 | 半自動 | QA | PR | screenshot | — |
| 103 | トースト通知確認 | 条件 | 自動 | DevUI | PR | screenshot | no_toast |
| 104 | 成功メッセージ確認 | 必須 | 自動 | QA | PR | screenshot | — |
| 105 | 多言語化確認 | 条件 | 半自動 | DevUI | release | screenshot | no_i18n |
| 106 | アクセシビリティ確認 | 必須 | 自動 | QA | PR | axe-core JSON | — |
| 107 | 色覚対応確認 | 条件 | 目視 | DevUI | release | screenshot（重要画面のみ） | — |
| 108 | 音声読み上げ確認 | 条件 | 目視 | QA | release | —（重要画面のみ） | — |
| 109 | 運用マニュアル整合 | 条件 | 目視 | Ops | release | — | — |
| 110 | 操作ログ出力確認 | 必須 | 自動 | Ops | PR | audit log | — |

---

## 8. APIテスト

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 111 | GET正常系 | 必須 | 自動 | DevAPI | PR | test log | — |
| 112 | POST正常系 | 必須 | 自動 | DevAPI | PR | test log | — |
| 113 | PUT正常系 | 必須 | 自動 | DevAPI | PR | test log | — |
| 114 | DELETE正常系 | 必須 | 自動 | DevAPI | PR | test log | — |
| 115 | HTTPステータス確認 | 必須 | 自動 | DevAPI | PR | test log | — |
| 116 | JSON形式確認 | 必須 | 自動 | DevAPI | PR | test log | — |
| 117 | NULL応答確認 | 必須 | 自動 | QA | PR | test log | — |
| 118 | 不正JSON確認 | 必須 | 自動 | QA | PR | test log | — |
| 119 | Content-Type確認 | 必須 | 自動 | DevAPI | PR | test log | — |
| 120 | APIタイムアウト確認 | 必須 | 自動 | QA | PR | test log | — |
| 121 | APIリトライ確認 | 条件 | 自動 | QA | PR | test log | no_retry |
| 122 | API認証確認 | 必須 | 自動 | Security | PR | test log | — |
| 123 | API認可確認 | 必須 | 自動 | Security | PR | test log | — |
| 124 | APIレート制限確認 | 条件 | 自動 | Security | PR | test log | no_rate_limit |
| 125 | API例外処理確認 | 必須 | 自動 | QA | PR | test log | — |
| 126 | APIログ確認 | 必須 | 半自動 | Ops | PR | API log | — |
| 127 | API監査ログ確認 | 必須 | 半自動 | Ops | PR | audit log | — |
| 128 | OpenAPI整合確認 | 必須 | 自動 | DevAPI | PR | contract test log | — |
| 129 | Swagger整合確認 | 必須 | 半自動 | DevAPI | PR | Swagger UI確認 | — |
| 130 | APIバージョン確認 | 条件 | 半自動 | DevAPI | release | — | no_versioning |

---

## 9. DBテスト

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 131 | DB接続確認 | 必須 | 自動 | DevAPI | PR | test log | — |
| 132 | 接続プール確認 | 条件 | 半自動 | Ops | nightly | metrics | no_connection_pool |
| 133 | CRUD確認 | 必須 | 自動 | DevAPI | PR | test log | — |
| 134 | トランザクション確認 | 必須 | 自動 | DevAPI | PR | test log | — |
| 135 | Rollback確認 | 必須 | 自動 | DevAPI | PR | test log | — |
| 136 | 排他制御確認 | 条件 | 自動 | DevAPI | PR | test log | no_concurrent_write |
| 137 | Index動作確認 | 条件 | 半自動 | DevAPI | nightly | EXPLAIN log | — |
| 138 | SQL性能確認 | 条件 | 半自動 | QA | nightly | slow query log | — |
| 139 | N+1問題確認 | 必須 | 自動 | QA | PR | ORM log | — |
| 140 | 大量データ確認 | 条件 | 半自動 | QA | nightly | performance log | — |
| 141 | SQL Injection対策 | 必須 | 自動 | Security | PR | SAST log | — |
| 142 | 文字コード確認 | 条件 | 半自動 | DevAPI | PR | test log | — |
| 143 | NULLデータ確認 | 必須 | 自動 | QA | PR | test log | — |
| 144 | 日付保存確認 | 条件 | 自動 | DevAPI | PR | test log | no_datetime |
| 145 | タイムゾーン確認 | 条件 | 自動 | DevAPI | PR | test log | no_timezone |
| 146 | Backup確認 | 必須 | 半自動 | Ops | nightly | backup log | — |
| 147 | Restore確認 | 条件 | 半自動 | Ops | release | restore test log | — |
| 148 | Migration確認 | 必須 | 自動 | DevAPI | PR | migration log | — |
| 149 | ORM整合確認 | 必須 | 自動 | DevAPI | PR | test log | — |
| 150 | DB障害時確認 | 条件 | 半自動 | Ops | release | incident simulation log | — |

---

## 10. バックエンドセキュリティ

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 151 | JWT認証確認 | 必須 | 自動 | Security | PR | test log | no_JWT |
| 152 | Session認証確認 | 必須 | 自動 | Security | PR | test log | no_session |
| 153 | OAuth確認 | 条件 | 半自動 | Security | PR | test log | no_OAuth |
| 154 | SAML確認 | 条件 | 目視 | Security | release | — | no_SAML |
| 155 | Entra ID連携確認 | 条件 | 半自動 | Security | release | test log | no_Entra_ID |
| 156 | HENNGE連携確認 | 条件 | 半自動 | Security | release | test log | no_HENNGE |
| 157 | LDAP/AD連携確認 | 条件 | 半自動 | Security | release | test log | no_LDAP |
| 158 | 権限昇格確認 | 必須 | 自動 | Security | PR | test log | — |
| 159 | IDOR確認 | 必須 | 自動 | Security | PR | test log | — |
| 160 | Command Injection確認 | 必須 | 自動 | Security | PR | SAST log | — |
| 161 | Path Traversal確認 | 必須 | 自動 | Security | PR | SAST log | — |
| 162 | SSRF確認 | 必須 | 自動 | Security | PR | SAST log | — |
| 163 | RCE確認 | 必須 | 自動 | Security | PR | SAST log | — |
| 164 | ファイルアップロード脆弱性 | 条件 | 自動 | Security | PR | test log | no_file_upload |
| 165 | Virus Scan確認 | 条件 | 半自動 | Security | PR | virus scan log | no_file_upload |
| 166 | 秘密情報管理確認 | 必須 | 自動 | Security | PR | secret scan log | — |
| 167 | .env漏洩確認 | 必須 | 自動 | Security | PR | secret scan log | — |
| 168 | HTTPS証明書確認 | 必須 | 半自動 | Ops | nightly | cert check log | — |
| 169 | TLSバージョン確認 | 必須 | 自動 | Security | PR | test log | — |
| 170 | Security Header確認 | 必須 | 自動 | Security | PR | security header log | — |

---

## 11. バックエンド性能試験

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 171 | 同時接続確認 | 条件 | 自動 | QA | nightly | load test log | — |
| 172 | 負荷試験 | 条件 | 半自動 | QA | release | load test report | — |
| 173 | ストレス試験 | 条件 | 半自動 | QA | release | stress test report | — |
| 174 | Soak Test | 条件 | 半自動 | QA | release | Soak test log | — |
| 175 | CPU使用率確認 | 条件 | 半自動 | Ops | nightly | metrics | — |
| 176 | メモリリーク確認 | 条件 | 半自動 | QA | nightly | memory profile | — |
| 177 | GC確認 | 条件 | 半自動 | QA | nightly | GC log | no_JVM |
| 178 | Queue確認 | 条件 | 自動 | DevAPI | PR | test log | no_queue |
| 179 | Redis確認 | 条件 | 自動 | DevAPI | PR | test log | no_Redis |
| 180 | Cache確認 | 条件 | 自動 | DevAPI | PR | test log | no_cache |
| 181 | 非同期Job確認 | 条件 | 自動 | DevAPI | PR | test log | no_async_job |
| 182 | Worker停止確認 | 条件 | 半自動 | Ops | release | incident simulation log | no_worker |
| 183 | Failover確認 | 条件 | 半自動 | Ops | release | incident simulation log | no_HA |
| 184 | Auto Recovery確認 | 条件 | 半自動 | Ops | release | incident simulation log | — |
| 185 | Kubernetes確認 | 条件 | 半自動 | Ops | release | k8s log | no_k8s |
| 186 | Docker確認 | 条件 | 自動 | CIManager | PR | CI log | no_docker |
| 187 | Container Restart確認 | 条件 | 半自動 | Ops | release | k8s log | no_container |
| 188 | ログ肥大化確認 | 条件 | 半自動 | Ops | nightly | log size metrics | — |
| 189 | Disk使用量確認 | 条件 | 半自動 | Ops | nightly | disk metrics | — |
| 190 | Thread枯渇確認 | 条件 | 半自動 | QA | nightly | thread metrics | — |

---

## 12. バッチ・ジョブ系

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 191 | 定期実行確認 | 必須 | 自動 | CIManager | nightly | cron log | — |
| 192 | Cron確認 | 必須 | 半自動 | Ops | nightly | cron log | — |
| 193 | 多重起動防止 | 必須 | 自動 | QA | PR | test log | — |
| 194 | リトライ確認 | 必須 | 自動 | QA | PR | test log | — |
| 195 | 失敗通知確認 | 必須 | 半自動 | Ops | PR | notification log | — |
| 196 | Mail通知確認 | 条件 | 半自動 | Ops | PR | mail log | no_mail |
| 197 | Teams通知確認 | 条件 | 半自動 | Ops | PR | Teams log | no_Teams |
| 198 | ログローテーション | 必須 | 自動 | Ops | nightly | log rotation log | — |
| 199 | 日跨ぎ確認 | 条件 | 半自動 | QA | nightly | test log | no_daily_batch |
| 200 | 月末処理確認 | 条件 | 目視 | QA | release | test log | no_month_end_batch |

---

## 13. 運用監視・ログ確認

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 201 | アプリログ確認 | 必須 | 半自動 | Ops | PR | app log | — |
| 202 | エラーログ確認 | 必須 | 自動 | Ops | PR | error log | — |
| 203 | 監査ログ確認 | 必須 | 半自動 | Ops | PR | audit log | — |
| 204 | 操作ログ確認 | 必須 | 半自動 | Ops | PR | operation log | — |
| 205 | Syslog確認 | 条件 | 半自動 | Ops | nightly | syslog | no_syslog |
| 206 | SIEM連携確認 | 条件 | 半自動 | Security | release | SIEM log | no_SIEM |
| 207 | メトリクス確認 | 必須 | 自動 | Ops | nightly | metrics | — |
| 208 | Prometheus確認 | 条件 | 自動 | Ops | nightly | Prometheus metrics | no_Prometheus |
| 209 | Grafana確認 | 条件 | 目視 | Ops | nightly | Grafana screenshot | no_Grafana |
| 210 | アラート通知確認 | 必須 | 半自動 | Ops | nightly | alert log | — |

---

## 14. 障害試験

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 211 | DB停止時 | 条件 | 半自動 | Ops | release | incident simulation log | — |
| 212 | API停止時 | 条件 | 半自動 | Ops | release | incident simulation log | — |
| 213 | Redis停止時 | 条件 | 半自動 | Ops | release | incident simulation log | no_Redis |
| 214 | NW断時 | 条件 | 目視 | Ops | release | — | — |
| 215 | DNS障害時 | 条件 | 半自動 | Ops | release | incident simulation log | — |
| 216 | SSL期限切れ時 | 条件 | 半自動 | Ops | nightly | cert expiry alert | — |
| 217 | ディスクFull時 | 条件 | 半自動 | Ops | release | incident simulation log | — |
| 218 | CPU100%時 | 条件 | 半自動 | Ops | release | stress test log | — |
| 219 | メモリ枯渇時 | 条件 | 半自動 | Ops | release | stress test log | — |
| 220 | Worker異常停止時 | 条件 | 半自動 | Ops | release | incident simulation log | no_worker |
| 221 | サーバ再起動時 | 条件 | 半自動 | Ops | release | incident simulation log | — |
| 222 | VM移行時 | 条件 | 目視 | Ops | release | — | no_VM |
| 223 | Windows Update後 | 条件 | 半自動 | Ops | release | smoke test log | no_Windows_server |
| 224 | Linux Patch後 | 条件 | 半自動 | Ops | release | smoke test log | no_Linux_server |
| 225 | 時刻同期ズレ確認 | 条件 | 半自動 | Ops | nightly | NTP check log | — |

---

## 15. AI開発系検証（ClaudeCode固有）

> **重要**: #227〜#230 および #247〜#250 はAI生成コードに特有のリスク。  
> AIが生成したSQL・正規表現・認可条件・ファイル操作は必ず Security Agent または人間のレビュー対象とする。

| # | 項目名 | 必須度 | 実行方法 | 担当Agent | タイミング | 証跡 | skip_if |
|---|---|---|---|---|---|---|---|
| 226 | 自動生成コード品質確認 | 必須 | 自動 | CIManager | PR | Linter log | — |
| 227 | AI生成SQL確認 ★ | 必須 | 半自動 | Security | PR | Security review | — |
| 228 | AI生成API確認 ★ | 必須 | 半自動 | Security | PR | Security review | — |
| 229 | AI生成HTML確認 ★ | 必須 | 自動 | Security | PR | SAST log | — |
| 230 | AI生成JS確認 ★ | 必須 | 自動 | Security | PR | SAST log | — |
| 231 | 型安全確認 | 必須 | 自動 | CIManager | PR | typecheck log | — |
| 232 | Linter確認 | 必須 | 自動 | CIManager | PR | lint log | — |
| 233 | Formatter確認 | 必須 | 自動 | CIManager | PR | format check log | — |
| 234 | UnitTest自動生成確認 | 必須 | 半自動 | QA | PR | test coverage log | — |
| 235 | E2E自動化確認 | 必須 | 自動 | Tester | PR | Playwright log | — |
| 236 | Playwright確認 | 必須 | 自動 | Tester | PR | Playwright log + screenshot | — |
| 237 | CI/CD確認 | 必須 | 自動 | CIManager | PR | CI URL | — |
| 238 | GitHub Actions確認 | 必須 | 自動 | CIManager | PR | CI URL | — |
| 239 | CodeRabbit確認 | 必須 | 半自動 | CIManager | PR | CodeRabbit report | — |
| 240 | Dependabot確認 | 必須 | 自動 | Security | nightly | Dependabot alert | — |
| 241 | Secret Scan確認 | 必須 | 自動 | Security | PR | secret scan log | — |
| 242 | SBOM確認 | 条件 | 自動 | Security | release | SBOM report | no_SBOM |
| 243 | OSSライセンス確認 | 条件 | 自動 | Security | release | license scan log | — |
| 244 | CLAUDE.md整合確認 | 必須 | 目視 | CIManager | PR | review checklist | — |
| 245 | Agent Team競合確認 | 必須 | 半自動 | CIManager | PR | WorkTree conflict check | — |
| 246 | WorkTree競合確認 | 必須 | 自動 | CIManager | PR | git conflict log | — |
| 247 | AutoFix暴走確認 ★ | 必須 | 半自動 | QA | PR | diff review（差分を必ずレビュー） | — |
| 248 | Loop暴走確認 ★ | 必須 | 自動 | CIManager | PR | loop count log | — |
| 249 | Token消費監視 | 必須 | 自動 | CIManager | PR | token usage log | — |
| 250 | AI誤修復確認 ★ | 必須 | 半自動 | QA | PR | diff review（全AutoFixに適用） | — |

---

## 運用ルール

### PRマージ前（Gate-1 + Gate-2）

- 変更ファイル近傍の必須項目を優先実行する
- 主要回帰テスト（#1・#22・#31・#51・#71・#111・#131・#141・#231〜#241）を必ず含める
- 未実行項目は「未実行理由」を終了報告に記載する

### リリース前（Gate-3）

- 全 250 項目のうち `必須` かつ `release` タイミングの項目を全件実行する
- `条件` 項目は skip_if 条件を評価してから実行可否を決定する
- 目視確認項目は人間がサインオフする

### AI生成コード重点確認（★マーク項目）

同一エラーの再修復は **2 回まで**。3 回目は停止して Issue 化する。  
AutoFix 後は必ず差分レビューを挟み、テストを通過してから次ループへ進む。

### 終了報告の必須3区分

```
## 検証サマリー
### 実行した検証（件数・証跡URL）
### 未実行の検証（件数・項目番号）
### 未実行理由
```

### WebUI案件での Verify フェーズ標準参加 Agent

`e2e-runner` と `security-reviewer` を Verify フェーズの必須参加 Agent とする。
