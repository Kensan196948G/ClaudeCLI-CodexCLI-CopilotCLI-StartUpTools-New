#!/usr/bin/env bats
# ============================================================
# cron-schedule.bats — bin/cron-schedule.sh 非対話サブコマンドのテスト
# 移植元: New-CronSchedule.ps1。crontab を PATH スタブ化して実行検証。
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export CRON_STORE="$TEST_TEMP/crontab.store"
  make_stub_bin crontab '
store="${CRON_STORE:?}"
case "${1:-}" in
  -l) [[ -f "$store" ]] && cat "$store" || exit 1 ;;
  -)  cat > "$store" ;;
  *)  exit 2 ;;
esac
'
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  cat > "$AI_STARTUP_CONFIG_PATH" <<JSON
{ "projects": "$TEST_TEMP/projects", "projectsDir": "$TEST_TEMP/projects" }
JSON
  mkdir -p "$TEST_TEMP/projects/MyProj/.git" "$TEST_TEMP/projects/Other/.git"
  export CCSU_CRON_LAUNCHER="$TEST_TEMP/cron-launcher.sh"
  export CCSU_CRON_LOGS_DIR="$TEST_TEMP/logs"
  export CCSU_SUP_DIR="$TEST_TEMP/sup"   # supervised 判定が実 ~/.claudeos を見ないように
  SCRIPT="$REPO_ROOT/bin/cron-schedule.sh"
}
teardown() { _bats_common_teardown; }

@test "add: 非対話で月〜土を登録" {
  run bash "$SCRIPT" add --project MyProj --time 21:00 --dow 1,2,3,4,5,6
  [ "$status" -eq 0 ]
  run cat "$CRON_STORE"
  [[ "$output" == *"# CLAUDEOS:"* ]]
  [[ "$output" == *"project=MyProj"* ]]
  [[ "$output" == *"0 21 * * 1,2,3,4,5,6"* ]]
}

@test "add: --project 欠落でエラー" {
  run bash "$SCRIPT" add --time 21:00 --dow 1
  [ "$status" -ne 0 ]
}

@test "add: --time 欠落でエラー" {
  run bash "$SCRIPT" add --project MyProj --dow 1
  [ "$status" -ne 0 ]
}

@test "add: デフォルト duration は 300" {
  bash "$SCRIPT" add --project MyProj --time 08:00 --dow 1
  run cat "$CRON_STORE"
  [[ "$output" == *"duration=300"* ]]
}

@test "list: 登録済みを曜日ラベル付きで表示" {
  bash "$SCRIPT" add --project MyProj --time 21:00 --dow 1 >/dev/null
  run bash "$SCRIPT" list
  [[ "$output" == *"project=MyProj"* ]]
  [[ "$output" == *"月"* ]]
}

@test "list: 空ならメッセージ" {
  run bash "$SCRIPT" list
  [[ "$output" == *"ありません"* ]]
}

@test "remove: id 指定で削除" {
  bash "$SCRIPT" add --project MyProj --time 21:00 --dow 1 >/dev/null
  id="$(grep -oP '# CLAUDEOS:\K[A-Za-z0-9_-]+' "$CRON_STORE" | head -1)"
  [ -n "$id" ]
  run bash "$SCRIPT" remove --id "$id"
  [ "$status" -eq 0 ]
  run cat "$CRON_STORE"
  [[ "$output" != *"$id"* ]]
}

@test "remove: --id 欠落でエラー" {
  run bash "$SCRIPT" remove
  [ "$status" -ne 0 ]
}

@test "remove-all: 全 CLAUDEOS エントリ削除" {
  bash "$SCRIPT" add --project A --time 21:00 --dow 1 >/dev/null
  bash "$SCRIPT" add --project B --time 08:00 --dow 2 >/dev/null
  bash "$SCRIPT" remove-all
  run bash "$SCRIPT" list
  [[ "$output" == *"ありません"* ]]
}

@test "run-now --foreground: cron-launcher.sh を同期で project/duration 付きで呼ぶ" {
  cat > "$CCSU_CRON_LAUNCHER" <<'EOF'
#!/usr/bin/env bash
echo "launcher called: $1 $2"
EOF
  chmod +x "$CCSU_CRON_LAUNCHER"
  run bash "$SCRIPT" run-now --project MyProj --duration 5 --foreground
  [[ "$output" == *"launcher called: MyProj 5"* ]]
}

@test "run-now: 既定は BG (メニューをブロックせず BG 起動メッセージ)" {
  cat > "$CCSU_CRON_LAUNCHER" <<'EOF'
#!/usr/bin/env bash
sleep 5; echo "should-not-block"
EOF
  chmod +x "$CCSU_CRON_LAUNCHER"
  run bash "$SCRIPT" run-now --project MyProj --duration 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"BG 起動: MyProj"* ]]
  [[ "$output" == *"claudeos-MyProj"* ]]
  # BG 用ログファイルが生成される
  run bash -c "ls '$CCSU_CRON_LOGS_DIR'/cron-*-MyProj.log 2>/dev/null | head -1"
  [ -n "$output" ]
}

@test "launch --project: 明示指定で BG 起動" {
  cat > "$CCSU_CRON_LAUNCHER" <<'EOF'
#!/usr/bin/env bash
true
EOF
  chmod +x "$CCSU_CRON_LAUNCHER"
  run bash "$SCRIPT" launch --project MyProj
  [ "$status" -eq 0 ]
  [[ "$output" == *"BG 起動: MyProj"* ]]
  [[ "$output" == *"1 件を BG 起動"* ]]
}

@test "launch --all: 登録済みを全件 BG 起動" {
  cat > "$CCSU_CRON_LAUNCHER" <<'EOF'
#!/usr/bin/env bash
true
EOF
  chmod +x "$CCSU_CRON_LAUNCHER"
  bash "$SCRIPT" add --project MyProj --time 21:00 --dow 1 >/dev/null
  bash "$SCRIPT" add --project Other --time 08:00 --dow 2 >/dev/null
  run bash "$SCRIPT" launch --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"BG 起動: MyProj"* ]]
  [[ "$output" == *"BG 起動: Other"* ]]
  [[ "$output" == *"2 件を BG 起動"* ]]
}

@test "launch --all: 登録ゼロなら警告して何もしない" {
  run bash "$SCRIPT" launch --all
  [ "$status" -eq 0 ]
  [[ "$output" != *"BG 起動:"* ]]
}

@test "bulk-register: dry-run で曜日分散の計画を表示 (実登録しない)" {
  run bash "$SCRIPT" bulk-register --dow 1,2 --start 9 --spacing 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  [[ "$output" == *"MyProj"* ]]
  [[ "$output" == *"月曜 09:00"* ]]
  # crontab には書かれない
  [[ "$output" != *"crontab 更新"* ]]
  run bash "$SCRIPT" list
  [[ "$output" == *"ありません"* ]]
}

@test "bulk-register --apply: crontab に登録される" {
  run bash "$SCRIPT" bulk-register --dow 1 --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"一括登録: 登録"* ]]
  run cat "$CRON_STORE"
  [[ "$output" == *"project=MyProj"* ]]
  [[ "$output" == *"project=Other"* ]]
}

@test "bulk-register --unmanaged-only: cron 登録済みを除外" {
  bash "$SCRIPT" add --project MyProj --time 21:00 --dow 1 >/dev/null
  run bash "$SCRIPT" bulk-register --unmanaged-only --dow 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 件"* ]]
  [[ "$output" == *"Other"* ]]
}

@test "不明サブコマンドでエラー" {
  run bash "$SCRIPT" frobnicate
  [ "$status" -ne 0 ]
}
