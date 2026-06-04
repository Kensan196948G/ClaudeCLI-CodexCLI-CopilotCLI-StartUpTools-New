#!/usr/bin/env bats
# ============================================================
# start-claude.bats — bin/start-claude.sh のテスト
# tmux/claude を PATH スタブ化。attach 回避のため background 中心。
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export TMUX_STATE="$TEST_TEMP/tmux-state"; mkdir -p "$TMUX_STATE"
  make_stub_bin tmux '
state="${TMUX_STATE:?}"; mkdir -p "$state"
sub="${1:-}"; shift || true
case "$sub" in
  has-session) [[ "${1:-}" == "-t" ]] && shift; [[ -f "$state/${1:-}" ]] && exit 0 || exit 1 ;;
  new-session) name=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-s" ]] && { name="${2:-}"; shift 2; continue; }; shift; done; [[ -n "$name" ]] && touch "$state/$name"; exit 0 ;;
  pipe-pane|attach) exit 0 ;;
  kill-session) [[ "${1:-}" == "-t" ]] && shift; rm -f "$state/${1:-}"; exit 0 ;;
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
  export CCSU_SKIP_ENV_FILE=1   # 実 ~/.env-claudeos を読み込まない (メール watcher を起動させない)
  SCRIPT="$REPO_ROOT/bin/start-claude.sh"
}
teardown() { _bats_common_teardown; }

@test "start-claude: --background で起動しセッション作成" {
  run bash "$SCRIPT" --project MyProj --background --duration 5
  [ "$status" -eq 0 ]
  [ -f "$TMUX_STATE/claudeos-MyProj" ]
}

@test "start-claude: project 不在でエラー" {
  run bash "$SCRIPT" --project NoSuch --background
  [ "$status" -ne 0 ]
}

@test "start-claude: --local 互換フラグを受理" {
  run bash "$SCRIPT" --project MyProj --local --background --duration 5
  [ "$status" -eq 0 ]
}

@test "start-claude: 不明な引数でエラー" {
  run bash "$SCRIPT" --project MyProj --frobnicate
  [ "$status" -ne 0 ]
}

@test "start-claude: background はログ案内を出す" {
  run bash "$SCRIPT" --project MyProj --background --duration 5
  [[ "$output" == *"バックグラウンド起動"* ]]
}
