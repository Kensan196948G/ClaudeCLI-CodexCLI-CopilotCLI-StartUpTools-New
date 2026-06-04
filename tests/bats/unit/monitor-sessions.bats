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
  # cron-manager 用 crontab スタブ (CRON_STORE 不在 → 登録なし)
  export CRON_STORE="$TEST_TEMP/crontab.store"
  make_stub_bin crontab '
store="${CRON_STORE:?}"
case "${1:-}" in
  -l) [[ -f "$store" ]] && cat "$store" || exit 1 ;;
  -)  cat > "$store" ;;
  *)  exit 2 ;;
esac
'
  # supervisor 状態ディレクトリ (空 → supervisor なし)
  export CCSU_SUP_DIR="$TEST_TEMP/sup"
  # config (全プロジェクト列挙 mon__all_projects 用)
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  printf '{ "projects": "%s/projects" }\n' "$TEST_TEMP" > "$AI_STARTUP_CONFIG_PATH"
  mkdir -p "$TEST_TEMP/projects/Alpha/.git" "$TEST_TEMP/projects/Beta/.git"
}
teardown() { _bats_common_teardown; }

# 登録 cron エントリを seed
_mon_seed_cron() {
  cat > "$CRON_STORE" <<EOF
# CLAUDEOS:abc12345 project=$1 duration=300 created=2026-01-01T00:00:00
0 21 * * 1,2,3,4,5,6 bash /x/cron-launcher.sh $1 300
EOF
}

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
  [[ "$output" == *"(実行中なし)"* ]]
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
  # コントロールセンターのタイトル
  [[ "$output" == *"コントロールセンター"* ]]
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

# ---- 登録 / supervisor セクション (Phase 2 コントロールセンター) ----
@test "mon__registered_projects: cron ∪ supervisor を一意列挙 (連結バグ回帰)" {
  _mon_seed_cron ProjA
  mkdir -p "$CCSU_SUP_DIR"
  echo '{ "project": "ProjB" }' > "$CCSU_SUP_DIR/ProjB.json"
  echo '{ "project": "ProjC" }' > "$CCSU_SUP_DIR/ProjC.json"
  run bash -c "source '$SCRIPT'; mon__registered_projects"
  [[ "$output" == *"ProjA"* ]]
  [[ "$output" == *"ProjB"* ]]
  [[ "$output" == *"ProjC"* ]]
  # supervisor 複数ファイルが改行なしで連結された幻のエントリが無いこと
  [[ "$output" != *"ProjBProjC"* ]]
  [[ "$output" != *"ProjCProjB"* ]]
  # ちょうど 3 行 (連結があれば 2 行や 4 行になる)
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
}

@test "mon__collect_registered: session稼働とsupervisor状態を出力" {
  _mon_seed_cron ProjA
  export MON_TEST_SESSIONS="claudeos-ProjA"
  mkdir -p "$CCSU_SUP_DIR"
  echo '{ "project": "ProjA", "status": "running", "restarts_today": 2, "minutes_today": 30 }' > "$CCSU_SUP_DIR/ProjA.json"
  run bash -c "source '$SCRIPT'; mon__collect_registered"
  [[ "$output" == *"ProjA|1|running|2|30"* ]]
}

@test "mon__remove_cron_for: 当該プロジェクトの cron を削除" {
  _mon_seed_cron ProjA
  run bash -c "source '$SCRIPT'; mon__remove_cron_for ProjA"
  [ "$output" = "1" ]
  run cat "$CRON_STORE"
  [[ "$output" != *"project=ProjA"* ]]
}

@test "--once: 登録セクションに cron プロジェクトを表示" {
  _mon_seed_cron ProjA
  export MON_TEST_SESSIONS=""
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"登録 / supervisor"* ]]
  [[ "$output" == *"ProjA"* ]]
}

@test "--once: 登録なしの案内" {
  export MON_TEST_SESSIONS=""
  run bash "$SCRIPT" --once
  [[ "$output" == *"登録なし"* ]]
}

# ---- 新規プロジェクトのオンボード (n キー / v3.4.3) ----
@test "mon__all_projects: config_projects_dir 配下の全dirを列挙" {
  run bash -c "source '$SCRIPT'; mon__all_projects"
  [[ "$output" == *"Alpha"* ]]
  [[ "$output" == *"Beta"* ]]
}

@test "mon__project_state_badge: 未管理は ⚪" {
  run bash -c "source '$SCRIPT'; mon__project_state_badge Alpha"
  [[ "$output" == *"未管理"* ]]
}

@test "mon__project_state_badge: cron 登録は 📅" {
  _mon_seed_cron Alpha
  run bash -c "source '$SCRIPT'; mon__project_state_badge Alpha"
  [[ "$output" == *"cron登録"* ]]
}

@test "mon__project_state_badge: 稼働中は 🟢" {
  export MON_TEST_SESSIONS="claudeos-Alpha"
  run bash -c "source '$SCRIPT'; mon__project_state_badge Alpha"
  [[ "$output" == *"稼働中"* ]]
}

@test "mon__project_state_badge: supervisor 稼働は 🔁" {
  mkdir -p "$CCSU_SUP_DIR"
  printf '{ "project":"Alpha","status":"running","pid":%s }\n' "$$" > "$CCSU_SUP_DIR/Alpha.json"
  run bash -c "source '$SCRIPT'; mon__project_state_badge Alpha"
  [[ "$output" == *"自律中"* ]]
}

@test "mon__is_github: .git + origin あれば 0" {
  git -C "$TEST_TEMP/projects/Alpha" init -q 2>/dev/null || skip "git なし"
  git -C "$TEST_TEMP/projects/Alpha" remote add origin https://example.com/x.git 2>/dev/null
  run bash -c "source '$SCRIPT'; mon__is_github Alpha"
  [ "$status" -eq 0 ]
}

@test "mon__is_github: .git なし/origin なしは非0" {
  mkdir -p "$TEST_TEMP/projects/PlainDir"   # .git を持たないディレクトリ
  run bash -c "source '$SCRIPT'; mon__is_github PlainDir"
  [ "$status" -ne 0 ]
}
