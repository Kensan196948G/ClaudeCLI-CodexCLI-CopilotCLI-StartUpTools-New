# 12-database-testing — データベース テスト検証・デバッグ指示

## 🎯 目的

DB の正確性・性能・セキュリティを全層で検証し、データ損失・不整合ゼロを維持する。

---

## 🗄 DB 基本検証

1. CRUD
2. Transaction
3. Commit/Rollback
4. FK 制約
5. Index
6. View
7. Procedure

---

## ⚡ パフォーマンス検証

1. Slow Query
2. Full Scan
3. Query Plan
4. Lock
5. Deadlock
6. Connection Pool
7. Cache Hit 率

---

## 🔄 データ整合性検証

1. NULL 制御
2. 型不一致
3. 文字コード
4. 日付型
5. 重複データ
6. Migration
7. Backup/Restore

---

## 🔐 DB セキュリティ検証

1. 認証
2. 権限制御
3. SQL Injection
4. 暗号化
5. 監査ログ
6. 接続元制限

---

## 🐞 DB デバッグ

```bash
EXPLAIN / Query Trace
Replication / WAL/Binlog
Buffer 確認 / Fragmentation
Connection Leak
```

---

## 🚫 禁止事項

- Migration 未確認のスキーマ変更
- トランザクション外の複数テーブル更新
- SQL Injection 対策なしのクエリ生成
