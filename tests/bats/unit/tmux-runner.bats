#!/usr/bin/env bats
# ============================================================
# tmux-runner.bats — lib/tmux-runner.sh のユニットテスト
# tmux/claude を PATH スタブ化。tmux 状態は $TMUX_STATE ディレクトリで管理。
# attach はブロッキングのため background モード中心に検証。
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export TMUX_STATE="$TEST_TEMP/tmux-state"
  mkdir -p "$TMUX_STATE"

  # tmux スタブ: セッションをファイルマーカーで再現
  make_stub_bin tmux '
state="${TMUX_STATE:?}"
mkdir -p "$state"
sub="${1:-}"; shift || true
case "$sub" in
  has-session)
    [[ "${1:-}" == "-t" ]] && shift
    [[ -f "$state/${1:-}" ]] && exit 0 || exit 1 ;;
  new-session)
    name=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "-s" ]]; then name="${2:-}"; shift 2; continue; fi
      shift
    done
    [[ -n "$name" ]] && touch "$state/$name"
    exit 0 ;;
  pipe-pane) exit 0 ;;
  attach) exit 0 ;;
  ls)
    if [[ -n "$(ls -A "$state" 2>/dev/null)" ]]; then
      for f in "$state"/*; do printf "%s: 1 windows\n" "$(basename "$f")"; done
      exit 0
    fi
    exit 1 ;;
  kill-session)
    [[ "${1:-}" == "-t" ]] && shift
    rm -f "$state/${1:-}"; exit 0 ;;
  *) exit 0 ;;
esac
'
  make_stub_bin claude 'exit 0'

  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  cat > "$AI_STARTUP_CONFIG_PATH" <<JSON
{ "projects": "$TEST_TEMP/projects", "projectsDir": "$TEST_TEMP/projects" }
JSON
  mkdir -p "$TEST_TEMP/projects/MyProj/.claude"
  export CLAUDEOS_HOME="$TEST_TEMP/claudeos"

  source "$REPO_ROOT/lib/tmux-runner.sh"
}
teardown() { _bats_common_teardown; }

@test "tmux__session_name: claudeos- プレフィックス + 安全化" {
  run tmux__session_name "My Proj"
  [ "$output" = "claudeos-My_Proj" ]
}

@test "tmux__is_running: 未起動なら非0" {
  run tmux__is_running MyProj
  [ "$status" -ne 0 ]
}

@test "tmux_run: background で detached 起動しセッションが作られる" {
  run tmux_run MyProj 300 background
  [ "$status" -eq 0 ]
  run tmux__is_running MyProj
  [ "$status" -eq 0 ]
}

@test "tmux_run: プロジェクト不在でエラー" {
  run tmux_run NoSuchProj 300 background
  [ "$status" -ne 0 ]
}

@test "tmux_run: background はログと接続案内を出す" {
  run tmux_run MyProj 120 background
  [[ "$output" == *"バックグラウンド起動"* ]]
  [[ "$output" == *"claudeos-MyProj"* ]]
}

@test "tmux_run: 既に起動中なら再起動せず案内" {
  tmux_run MyProj 300 background
  run tmux_run MyProj 300 background
  [[ "$output" == *"既に起動中"* ]]
}

@test "tmux_run: ログディレクトリを作成する" {
  tmux_run MyProj 300 background
  [ -d "$CLAUDEOS_HOME/logs" ]
}

@test "tmux__status: セッションがあれば claudeos- を列挙" {
  tmux_run MyProj 300 background
  run tmux__status
  [[ "$output" == *"claudeos-MyProj"* ]]
}

@test "tmux__status: なければメッセージ" {
  run tmux__status
  [[ "$output" == *"セッションなし"* ]]
}

@test "tmux__stop: 起動中セッションを停止" {
  tmux_run MyProj 300 background
  run tmux__stop MyProj
  [ "$status" -eq 0 ]
  run tmux__is_running MyProj
  [ "$status" -ne 0 ]
}

@test "tmux__stop: 不在セッションは警告して非0" {
  run tmux__stop NoSuchProj
  [ "$status" -ne 0 ]
}

# ---- 終了レポートメール (手動セッション) ----------------------

@test "tmux__send_report: EMAIL_ENABLED 未設定なら python3 を呼ばない" {
  make_stub_bin python3 'echo called > "$TEST_TEMP/py-called"; exit 0'
  CCSU_REPORT_SCRIPT="$TEST_TEMP/report.py"; : > "$CCSU_REPORT_SCRIPT"
  run tmux__send_report sid "$TEST_TEMP/log" completed s e 5 Proj
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP/py-called" ]
}

@test "tmux__send_report: 有効時 report-and-mail.py を引数付きで呼ぶ" {
  export CLAUDEOS_EMAIL_ENABLED=1
  make_stub_bin python3 'echo "$@" > "$TEST_TEMP/py-called"; exit 0'
  CCSU_REPORT_SCRIPT="$TEST_TEMP/report.py"; : > "$CCSU_REPORT_SCRIPT"
  run tmux__send_report "manual-123-MyProj" "$TEST_TEMP/log" completed "2026-06-02T12:00:00" "2026-06-02T12:05:00" 5 "MyProj"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP/py-called" ]
  grep -q -- "--session" "$TEST_TEMP/py-called"
  grep -q "manual-123-MyProj" "$TEST_TEMP/py-called"
  grep -q "completed" "$TEST_TEMP/py-called"
}

@test "tmux__send_report: 有効でも report スクリプト不在なら skip" {
  export CLAUDEOS_EMAIL_ENABLED=1
  make_stub_bin python3 'echo called > "$TEST_TEMP/py-called"; exit 0'
  CCSU_REPORT_SCRIPT="$TEST_TEMP/does-not-exist.py"
  run tmux__send_report sid "$TEST_TEMP/log" completed s e 5 Proj
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP/py-called" ]
}

@test "tmux__send_report: CLAUDEOS_MANUAL_EMAIL=0 で手動メールのみ無効化" {
  export CLAUDEOS_EMAIL_ENABLED=1 CLAUDEOS_MANUAL_EMAIL=0
  make_stub_bin python3 'echo called > "$TEST_TEMP/py-called"; exit 0'
  CCSU_REPORT_SCRIPT="$TEST_TEMP/report.py"; : > "$CCSU_REPORT_SCRIPT"
  run tmux__send_report sid "$TEST_TEMP/log" completed s e 5 Proj
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP/py-called" ]
}

@test "tmux_run: EMAIL_ENABLED=1 で終了レポート watcher を起動する案内" {
  export CLAUDEOS_EMAIL_ENABLED=1
  make_stub_bin setsid 'exit 0'   # 実 watcher は起動させずスパーン経路のみ通す
  run tmux_run MyProj 5 background
  [ "$status" -eq 0 ]
  [[ "$output" == *"終了時にレポート送信"* ]]
}

@test "tmux_run: EMAIL_ENABLED 未設定なら watcher 案内を出さない" {
  run tmux_run MyProj 5 background
  [ "$status" -eq 0 ]
  [[ "$output" != *"終了時にレポート送信"* ]]
}
