# 完全自律開発対応チェックリスト

> **対象**: ClaudeOS v8.2 / Linux Cron 自律実行 (v3.2.70+)  
> **目的**: プロジェクトを Linux cron に登録した後、人手なしで自律開発が回るかを確認する

---

## チェックリスト（7項目）

プロジェクトごとに以下を確認してください。全て ✅ になれば次回 Cron 発火から自律実行します。

| # | 確認項目 | 確認コマンド / 方法 | 状態 |
|---|---|---|---|
| 1 | **Cron 登録済み** | `crontab -l \| grep CLAUDEOS` (Linux) | ☐ |
| 2 | **`state.json` 生成済み** | `test -f ~/Projects/<project>/state.json` (Linux) | ☐ |
| 3 | **`CLAUDE.md` 配備済み** | `test -f ~/Projects/<project>/.claude/CLAUDE.md` (Linux) | ☐ |
| 4 | **`START_PROMPT.md` 配備済み** | `test -f ~/Projects/<project>/.claude/START_PROMPT.md` (Linux) | ☐ |
| 5 | **Claude 認証済み** | `claude --version` が通ること (Linux) | ☐ |
| 6 | **git リポジトリ有り・リモート設定済み** | `git -C ~/Projects/<project> remote -v` | ☐ |
| 7 | **メール通知設定済み（任意）** | `grep CLAUDEOS_EMAIL_ENABLED ~/.env-claudeos` | ☐ |

---

## 各項目の確認・対処方法

### 1. Cron 登録済み

```bash
# Linux サーバーで確認
crontab -l | grep CLAUDEOS
```

未登録の場合はメニュー 14 (`New-CronSchedule.ps1`) から登録してください。

**登録済みの例:**
```
# CLAUDEOS:adf58d9b project=ITSM-System duration=300 created=2026-04-17
30 8 * * 1 ~/.claudeos/cron-launcher.sh ITSM-System 300 >> ~/.claudeos/logs/...
```

---

### 2. state.json 生成済み

```bash
# Linux サーバーで確認
ls -la ~/Projects/<project>/state.json
```

**未存在の場合 — 自動生成コマンド:**
```bash
cd ~/Projects/<project>
# state.json.example から複製して最低限の設定を入力
cp /path/to/state.json.example state.json
# または最小構成を直接作成
cat > state.json << 'EOF'
{
  "goal": { "title": "<プロジェクト名> 自律開発" },
  "kpi": { "success_rate_target": 0.9 },
  "execution": { "phase": "Monitor", "max_duration_minutes": 300 },
  "stable": { "consecutive_success": 0, "target_n": 3, "stable_achieved": false },
  "automation": { "auto_issue_generation": true, "self_evolution": true }
}
EOF
```

---

### 3. CLAUDE.md 配備済み

```bash
# .claude/ ディレクトリが存在するか確認
ls ~/Projects/<project>/.claude/CLAUDE.md
```

**未存在の場合:**
```bash
mkdir -p ~/Projects/<project>/.claude
# Windows 側からテンプレートを展開するか、Start-ClaudeCode.ps1 で S1 起動時に自動配備される
```

---

### 4. START_PROMPT.md 配備済み

```bash
ls ~/Projects/<project>/.claude/START_PROMPT.md
```

**未存在の場合 — 最低限の内容:**
```bash
cat > ~/Projects/<project>/.claude/START_PROMPT.md << 'EOF'
# <プロジェクト名> — 自律開発セッション

Monitor → Build → Verify → Improve の順でループを進めてください。
state.json の goal と kpi を参照して優先課題を選定し、
Issue 駆動で PR を作成してください。
EOF
```

---

### 5. Claude 認証済み

```bash
# Linux サーバーで確認
claude --version
claude auth status 2>/dev/null || echo "要認証"
```

**未認証の場合:**
```bash
claude auth login
# または ANTHROPIC_API_KEY を ~/.env-claudeos に設定
echo 'export ANTHROPIC_API_KEY=your-key-here' >> ~/.env-claudeos
```

---

### 6. git リポジトリ・リモート設定済み

```bash
git -C ~/Projects/<project> remote -v
```

**未設定の場合:**
```bash
cd ~/Projects/<project>
git init
git remote add origin https://github.com/<owner>/<project>.git
git push -u origin main
```

---

### 7. メール通知設定済み（任意）

```bash
grep CLAUDEOS_EMAIL ~/.env-claudeos 2>/dev/null || echo "未設定"
```

**設定する場合 (`~/.env-claudeos` に追記):**
```bash
export CLAUDEOS_EMAIL_ENABLED=1
export CLAUDEOS_SMTP_USER=your@gmail.com
export CLAUDEOS_SMTP_PASS=your-app-password
export CLAUDEOS_DEFAULT_TO=your@gmail.com
```

---

## 初回セットアップ〜完全自律まで の時系列フロー

```
[ユーザー操作]
  1. メニュー 14 で New-CronSchedule.ps1 を起動
  2. プロジェクト名・曜日・時刻・時間を選択
  3. Linux cron に登録される

[自動実行 - 次回 Cron 発火時]
  4. cron-launcher.sh が起動
  5. ~/Projects/<project>/.claude/START_PROMPT.md を読み込む
  6. `claude --dangerously-skip-permissions <START_PROMPT>` を実行
  7. Claude が state.json を読んでフェーズを確認
  8. Monitor → Build → Verify → Improve のループを実行
  9. PR 作成・マージ・state.json 更新
  10. 5時間後 timeout → メール通知 → 次回 Cron まで待機

[継続]
  毎週同じ曜日・時刻に繰り返し → 完全無人運用
```

---

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| Cron が発火しない | crontab の記述エラー | `crontab -l` で構文確認 |
| Claude が起動しない | PATH 未設定 | `cron-launcher.sh` 内の PATH を確認 |
| git push が失敗する | 認証切れ | `gh auth login` または `ANTHROPIC_API_KEY` を更新 |
| state.json なしで起動する | 未生成 | チェック項目 2 の対処参照 |
| タイムアウトが早い | duration 設定 | `crontab -l` で duration 値を確認・修正 |

---

## 関連ファイル

| ファイル | 役割 |
|---|---|
| `Claude/templates/linux/cron-launcher.sh` | 自律実行エントリポイント |
| `Claude/templates/linux/report-and-mail.py` | セッション完了メール送信 |
| `Claude/templates/claude/CLAUDE.md` | プロジェクト配備用ポリシーテンプレート |
| `Claude/templates/claude/START_PROMPT.md` | プロジェクト配備用プロンプトテンプレート |
| `state.json.example` | state.json の初期値テンプレート |
| `scripts/main/New-CronSchedule.ps1` | Cron 登録 UI（メニュー 14） |
