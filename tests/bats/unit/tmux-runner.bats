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
{ "linuxBase": "$TEST_TEMP/projects", "projectsDir": "$TEST_TEMP/projects" }
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
