# 11-infrastructure-testing — インフラ テスト検証・デバッグ指示

## 🎯 目的

サーバ・ネットワーク・ストレージ・監視の全インフラ層を検証し、可用性と耐障害性を確認する。

---

## 🖥 サーバ検証

1. Linux
2. Windows Server
3. systemd
4. Cron
5. Docker
6. Kubernetes
7. VM
8. NTP

---

## 🌐 ネットワーク検証

1. DNS
2. Ping
3. HTTPS
4. Firewall
5. VPN
6. Proxy
7. LoadBalancer
8. Port 確認

---

## 💾 ストレージ検証

1. Disk 容量
2. IOPS
3. Backup
4. Restore
5. Snapshot
6. RAID
7. NAS
8. SMB/NFS

---

## 📈 監視・運用検証

1. CPU 監視
2. Memory 監視
3. Disk 監視
4. Alert 通知
5. Grafana
6. Prometheus
7. Zabbix
8. 自動復旧

---

## 🔥 障害試験（重要）

| シナリオ | 確認内容 |
|---|---|
| DB 停止時 | API フォールバック動作 |
| API 停止時 | フロントエンドのエラー表示 |
| Redis 停止時 | キャッシュ迂回動作 |
| NW 断時 | タイムアウト・リトライ |
| Disk Full 時 | ログローテーション動作 |
| Container Restart | 自動復旧確認 |

---

## 🐞 インフラデバッグ

```bash
journalctl / dmesg
OOM 確認 / Docker Logs
tcpdump / Wireshark
SSH Logs / Kernel Panic
```
