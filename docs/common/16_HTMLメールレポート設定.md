# 16. HTML メールレポート設定 (ClaudeOS v3.2.0)

## Summary

Cron で起動された ClaudeCode セッションが終了するたびに、実行サマリ・所要時間・次フェーズ提案を含む **HTML 形式のレポートメール** を Gmail SMTP 経由で `kensan1969@gmail.com` に送信する機能のセットアップ手順です。

## Risks

- Gmail アプリパスワードを `.bashrc` に書くため、**ユーザーアカウント以外がアクセスできる状態にしない**(`chmod 600 ~/.bashrc`)。
- 公開リポジトリ・公開バックアップに `.bashrc` を含めない。`config.json` にはパスワードを書かない設計です。
- アプリパスワードが漏洩した場合は Google アカウントの「アプリパスワード」画面で即時失効可能。

## Findings

### 機能概要

`cron-launcher.sh` が `finalize` トラップ内で `report-and-mail.py` を呼び出し、以下を含む HTML メールを送信します。

| 項目 | 内容 |
|---|---|
| ステータス | 🟢 completed / 🔴 failed / 🟡 timeout |
| 開始 / 終了時刻 | ISO 8601 → `YYYY-MM-DD HH:MM:SS` 形式 |
| 総作業時間 | `H 時間 M 分 S 秒` |
| プロジェクト名 | cron 引数の project |
| セッション ID | `YYYYMMDD-HHMMSS-<project>` |
| ログ末尾 15 行 | プレーンテキスト(色付きコードブロック) |
| 実行サマリー | Monitor / Development / Verify / Improvement の出現回数、エラー検出数、STABLE 達成有無 |
| 次の開発フェーズ | ステータス + ログ集計から自動提案 |

### セットアップ手順 (Linux 側)

#### 手順 1 — Gmail アプリパスワードの取得(取得済みの場合はスキップ)

1. https://myaccount.google.com/security にアクセス
2. 「2 段階認証プロセス」を有効化(まだの場合)
3. https://myaccount.google.com/apppasswords にアクセス
4. アプリ名(任意): `ClaudeOS Cron Report` 等を入力 → 作成
5. 表示される **16 桁のパスワード**(スペース付き表示)を控える
   - 例: `abcd efgh ijkl mnop` → 実際は `abcdefghijklmnop`(スペースなしで使用)

#### 手順 2 — Linux 環境変数の設定(アプリパスワードの配置)

SSH で Linux ホストに接続後、`~/.bashrc` の **末尾** に以下を追記:

```bash
# ----- ClaudeOS v3.2.0 SMTP credentials -----
export CLAUDEOS_SMTP_USER="kensan1969@gmail.com"
export CLAUDEOS_SMTP_PASS="abcdefghijklmnop"   # 手順 1 で取得した 16 桁(スペース除去)
```

権限を絞ります(他ユーザーから読めないように):

```bash
chmod 600 ~/.bashrc
```

シェルを再起動するか、cron 用に system-wide 環境変数として設定する場合は:

```bash
# cron は ~/.bashrc を読まないため、以下のいずれかが必要
# 方式 A: crontab 内で直接 export (推奨、cron-launcher.sh が継承)
crontab -e
# 先頭に以下を追記
# CLAUDEOS_SMTP_USER=kensan1969@gmail.com
# CLAUDEOS_SMTP_PASS=abcdefghijklmnop

# 方式 B: cron-launcher.sh の冒頭で source ~/.env-claudeos
mkdir -p ~ && cat > ~/.env-claudeos <<'EOF'
export CLAUDEOS_SMTP_USER="kensan1969@gmail.com"
export CLAUDEOS_SMTP_PASS="abcdefghijklmnop"
EOF
chmod 600 ~/.env-claudeos
# その後、cron-launcher.sh の冒頭に以下を追記:
#   [[ -f ~/.env-claudeos ]] && source ~/.env-claudeos
```

> ⚠️ **重要**: cron は対話シェルではないため `~/.bashrc` を **読みません**。方式 A(crontab 内 export)または方式 B(env ファイル source)を必ず使用してください。

#### 手順 3 — report-and-mail.py の配置

リポジトリの `Claude/templates/linux/report-and-mail.py` を Linux ホストにコピー:

```bash
# Windows 側から SCP で送る例
scp Claude/templates/linux/report-and-mail.py kensan@<your-linux-host>:~/.claudeos/

# Linux 側で実行権限を付ける
ssh kensan@<your-linux-host> 'chmod +x ~/.claudeos/report-and-mail.py'
```

または、メニュー経由のデプロイスクリプト(将来的に追加予定)で一括配置可能です。

#### 手順 4 — cron-launcher.sh の更新

リポジトリの `Claude/templates/linux/cron-launcher.sh` を Linux ホストにコピー:

```bash
scp Claude/templates/linux/cron-launcher.sh kensan@<your-linux-host>:~/.claudeos/
ssh kensan@<your-linux-host> 'chmod +x ~/.claudeos/cron-launcher.sh'
```

`finalize` トラップ内で `report-and-mail.py` が **best-effort** で呼ばれます。Python 3 が無い・スクリプトが無い場合はスキップ(cron 全体は成功扱い)。

#### 手順 5 — config.json の有効化(任意)

`config/config.json` の `email.enabled` を `true` に変更(現状は表示用、将来 Windows メニューで読み取る予定):

```json
"email": {
  "enabled": true,
  ...
}
```

### 動作確認(dry-run)

メール送信前に HTML プレビューを stdout に出力するモードがあります:

```bash
ssh kensan@<your-linux-host> '
  python3 ~/.claudeos/report-and-mail.py \
    --session test-001 \
    --log ~/.claudeos/logs/cron-test.log \
    --status completed \
    --start "$(date -Iseconds)" \
    --end "$(date -Iseconds)" \
    --duration-min 300 \
    --project test-project \
    --dry-run
' > preview.html

# Windows 側で preview.html を開いて HTML 表示を確認
```

### 実機テスト送信

```bash
ssh kensan@<your-linux-host> '
  source ~/.env-claudeos 2>/dev/null || true
  python3 ~/.claudeos/report-and-mail.py \
    --session smoke-test-$(date +%s) \
    --log ~/.claudeos/logs/cron-test.log \
    --status completed \
    --start "$(date -Iseconds)" \
    --end "$(date -Iseconds)" \
    --duration-min 300 \
    --project smoke-test
'
```

数秒以内に `kensan1969@gmail.com` 宛に HTML メールが届けば成功。

## Next Action

- [ ] `~/.bashrc` または `~/.env-claudeos` に SMTP 認証情報を配置
- [ ] `report-and-mail.py` を `~/.claudeos/` に配置(`chmod +x` 付き)
- [ ] `cron-launcher.sh` を v3.2.0 版で上書き(`chmod +x` 付き)
- [ ] `--dry-run` で HTML プレビュー確認
- [ ] 実機テスト送信で受信確認
- [ ] 次回 cron 自動起動で実運用検証(週末 21:00 等)

## Troubleshooting

| 症状 | 原因 | 対処 |
|---|---|---|
| メールが届かない・ログに `WARN: CLAUDEOS_SMTP_USER ... 未設定` | cron 環境に環境変数が渡っていない | crontab 内で直接 `export` するか `source ~/.env-claudeos` を `cron-launcher.sh` 冒頭で実行 |
| `(535, b'5.7.8 Username and Password not accepted')` | アプリパスワードが間違っている / 2 段階認証が無効 | 手順 1 から再取得。スペースを除去しているか確認 |
| HTML が文字化けする | Gmail の表示問題は稀。SMTP は UTF-8 で送信済み | クライアント側のエンコーディング設定を確認 |
| ログ末尾が空 | cron-launcher.sh 実行直後で書き込みが終わっていない | 通常は `finalize` 後に呼ばれるため発生しないが、ログ消失時はプレーンテキスト fallback が動作 |
| `command not found: python3` | Python 3 が Linux ホストに未インストール | `sudo apt install python3` 等で導入。標準ライブラリのみ使用するため追加 pip 不要 |
