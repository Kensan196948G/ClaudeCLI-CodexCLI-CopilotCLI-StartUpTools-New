#!/usr/bin/env bats
# ============================================================
# monitor-sessions.bats — bin/monitor-sessions.sh のユニットテスト
#   純粋ヘルパ (mon__fmt_hms / mon__status_icon) と、tmux スタブによる
#   --once 描画 / セッション列挙フィルタを検証する。
#   tmux スタブは環境変数 MON_TEST_* でセッション表を表現する。
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export CLAUDEOS_PLAIN_OUTPUT=1
  SCRIPT="$REPO_ROOT/bin/monitor-sessions.sh"

  # tmux スタブ: MON_TEST_SESSIONS (空白区切り) をセッション表として応答
  make_stub_bin tmux '
case "${1:-}" in
  list-sessions)
    for s in ${MON_TEST_SESSIONS:-}; do echo "$s"; done ;;
  has-session)
    shift; [[ "${1:-}" == "-t" ]] && shift; nm="${1:-}"
    for s in ${MON_TEST_SESSIONS:-}; do [[ "$s" == "$nm" ]] && exit 0; done
    exit 1 ;;
  display-message)
    echo "${MON_TEST_CREATED:-0}" ;;
  show-options)
    last="${@: -1}"
    case "$last" in
      @ccsu_duration_min) echo "${MON_TEST_DUR:-}" ;;
      @ccsu_project)      echo "${MON_TEST_PROJ:-}" ;;
      *) : ;;
    esac ;;
  list-windows) exit 0 ;;
  *) exit 0 ;;
esac
'
}
teardown() { _bats_common_teardown; }

# ---- 純粋ヘルパ: mon__fmt_hms --------------------------------
@test "mon__fmt_hms: 3661 → 01:01:01" {
  run bash -c "source '$SCRIPT'; mon__fmt_hms 3661"
  [ "$output" = "01:01:01" ]
}

@test "mon__fmt_hms: 0 → 00:00:00" {
  run bash -c "source '$SCRIPT'; mon__fmt_hms 0"
  [ "$output" = "00:00:00" ]
}

@test "mon__fmt_hms: 負値は 00:00:00 に丸める" {
  run bash -c "source '$SCRIPT'; mon__fmt_hms -10"
  [ "$output" = "00:00:00" ]
}

@test "mon__fmt_hms: 非数は 00:00:00" {
  run bash -c "source '$SCRIPT'; mon__fmt_hms abc"
  [ "$output" = "00:00:00" ]
}

@test "mon__fmt_hms: 59 → 00:00:59" {
  run bash -c "source '$SCRIPT'; mon__fmt_hms 59"
  [ "$output" = "00:00:59" ]
}

# ---- 純粋ヘルパ: mon__status_icon ---------------------------
@test "mon__status_icon: 残り潤沢 → ✽" {
  run bash -c "source '$SCRIPT'; mon__status_icon 1000 1"
  [ "$output" = "✽" ]
}

@test "mon__status_icon: 残り<=300 → ⚠" {
  run bash -c "source '$SCRIPT'; mon__status_icon 100 1"
  [ "$output" = "⚠" ]
}

@test "mon__status_icon: 残り<=0 → ⏱" {
  run bash -c "source '$SCRIPT'; mon__status_icon -5 1"
  [ "$output" = "⏱" ]
}

@test "mon__status_icon: 残り不明(has=0) → ✽" {
  run bash -c "source '$SCRIPT'; mon__status_icon 0 0"
  [ "$output" = "✽" ]
}

# ---- セッション列挙フィルタ --------------------------------
@test "mon__project_sessions: monitor と非 claudeos- を除外" {
  export MON_TEST_SESSIONS="claudeos-A claudeos-monitor _keeper_A claudeos-B other"
  run bash -c "source '$SCRIPT'; mon__project_sessions"
  [[ "$output" == *"claudeos-A"* ]]
  [[ "$output" == *"claudeos-B"* ]]
  [[ "$output" != *"claudeos-monitor"* ]]
  [[ "$output" != *"_keeper_A"* ]]
  [[ "$output" != *"other"* ]]
}

# ---- --once 描画 -------------------------------------------
@test "--once: 実行中なしで案内メッセージ" {
  export MON_TEST_SESSIONS=""
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"実行中の ClaudeOS セッションなし"* ]]
}

@test "--once: duration ありで経過/残りと プロジェクト名を表示" {
  export MON_TEST_SESSIONS="claudeos-MyProj"
  export MON_TEST_CREATED=$(( $(date +%s) - 3600 ))
  export MON_TEST_DUR=300
  export MON_TEST_PROJ="MyProj"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"MyProj"* ]]
  # HH:MM:SS 形式の経過/残りが描画される
  [[ "$output" =~ [0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]
  # duration があるので残りは — ではない
  [[ "$output" == *"ライブ監視"* ]]
}

@test "--once: duration 無しは残り — 表示" {
  export MON_TEST_SESSIONS="claudeos-NoDur"
  export MON_TEST_CREATED=$(( $(date +%s) - 120 ))
  export MON_TEST_DUR=""
  export MON_TEST_PROJ="NoDur"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"NoDur"* ]]
  [[ "$output" == *"—"* ]]
}

# ---- usage / 引数 ------------------------------------------
@test "--help: 使い方とキー操作を表示" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: monitor-sessions.sh"* ]]
  [[ "$output" == *"Ctrl-b 0"* ]]
}

@test "不明な引数でエラー" {
  run bash "$SCRIPT" frobnicate
  [ "$status" -ne 0 ]
}
