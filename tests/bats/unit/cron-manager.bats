#!/usr/bin/env bats
# ============================================================
# cron-manager.bats — lib/cron-manager.sh のユニットテスト
# 移植元: tests/unit/CronManager.Tests.ps1
# crontab は PATH スタブ ($CRON_STORE ファイル) で差し替え
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  # crontab スタブ: ファイルをストアに crontab -l / crontab - を再現
  export CRON_STORE="$TEST_TEMP/crontab.store"
  make_stub_bin crontab '
store="${CRON_STORE:?CRON_STORE unset}"
case "${1:-}" in
  -l) [[ -f "$store" ]] && cat "$store" || exit 1 ;;
  -)  cat > "$store" ;;
  *)  exit 2 ;;
esac
'
  export CCSU_CRON_LAUNCHER="$TEST_TEMP/cron-launcher.sh"
  export CCSU_CRON_LOGS_DIR="$TEST_TEMP/logs"
  source "$REPO_ROOT/lib/cron-manager.sh"
}
teardown() { _bats_common_teardown; }

# --- cron__format_expr ---

@test "cron__format_expr: 単一曜日" {
  run cron__format_expr 21:00 1
  [ "$status" -eq 0 ]
  [ "$output" = "0 21 * * 1" ]
}

@test "cron__format_expr: 月〜土 (1 2 3 4 5 6)" {
  run cron__format_expr 09:30 1 2 3 4 5 6
  [ "$output" = "30 9 * * 1,2,3,4,5,6" ]
}

@test "cron__format_expr: 重複曜日を排除しソート" {
  run cron__format_expr 12:00 3 1 3 2
  [ "$output" = "0 12 * * 1,2,3" ]
}

@test "cron__format_expr: 境界値 00:00 日曜" {
  run cron__format_expr 00:00 0
  [ "$output" = "0 0 * * 0" ]
}

@test "cron__format_expr: 境界値 23:59 土曜" {
  run cron__format_expr 23:59 6
  [ "$output" = "59 23 * * 6" ]
}

@test "cron__format_expr: 不正な時 (25時) でエラー" {
  run cron__format_expr 25:00 1
  [ "$status" -ne 0 ]
}

@test "cron__format_expr: 不正な分 (99分) でエラー" {
  run cron__format_expr 10:99 1
  [ "$status" -ne 0 ]
}

@test "cron__format_expr: 不正な曜日 (7) でエラー" {
  run cron__format_expr 10:00 7
  [ "$status" -ne 0 ]
}

@test "cron__format_expr: HH:MM 形式でない入力でエラー" {
  run cron__format_expr "9am" 1
  [ "$status" -ne 0 ]
}

# --- cron__new_id / cron__dow_label ---

@test "cron__new_id: 8 桁" {
  run cron__new_id
  [ "${#output}" -eq 8 ]
}

@test "cron__new_id: 呼ぶたびに異なる" {
  a="$(cron__new_id)"; b="$(cron__new_id)"
  [ "$a" != "$b" ]
}

@test "cron__dow_label: 0=日 1=月 6=土" {
  [ "$(cron__dow_label 0)" = "日" ]
  [ "$(cron__dow_label 1)" = "月" ]
  [ "$(cron__dow_label 6)" = "土" ]
}

@test "cron__dow_label: 範囲外は ?" {
  [ "$(cron__dow_label 9)" = "?" ]
}

# --- cron__add ---

@test "cron__add: 追加後 cron__list で取得できる" {
  id="$(cron__add MyProj 300 21:00 1 2 3 4 5 6)"
  [ -n "$id" ]
  run cron__list
  [ "$status" -eq 0 ]
  [[ "$output" == *"${id}|MyProj|300|"*"|0 21 * * 1,2,3,4,5,6" ]]
}

@test "cron__add: crontab に # CLAUDEOS コメントと launcher コマンドが入る" {
  cron__add MyProj 120 08:00 1 >/dev/null
  run cat "$CRON_STORE"
  [[ "$output" == *"# CLAUDEOS:"* ]]
  [[ "$output" == *"project=MyProj"* ]]
  [[ "$output" == *"cron-launcher.sh MyProj 120"* ]]
}

@test "cron__add: 既存の他人 cron を壊さない" {
  printf '%s\n' "0 5 * * * /usr/bin/other-job" > "$CRON_STORE"
  cron__add MyProj 300 21:00 1 >/dev/null
  run cat "$CRON_STORE"
  [[ "$output" == *"other-job"* ]]
  [[ "$output" == *"CLAUDEOS"* ]]
}

@test "cron__add: crontab の % が \\% にエスケープされる" {
  cron__add MyProj 300 21:00 1 >/dev/null
  run cat "$CRON_STORE"
  [[ "$output" == *'\%Y'* ]]
}

# --- cron__remove / cron__remove_all ---

@test "cron__remove: id 指定で該当エントリのみ削除" {
  id1="$(cron__add ProjA 300 21:00 1)"
  id2="$(cron__add ProjB 120 08:00 2)"
  run cron__remove "$id1"
  [ "$output" = "1" ]
  run cron__list
  [[ "$output" != *"$id1"* ]]
  [[ "$output" == *"$id2"* ]]
}

@test "cron__remove: 他人 cron は残す" {
  printf '%s\n' "0 5 * * * /usr/bin/other-job" > "$CRON_STORE"
  id="$(cron__add MyProj 300 21:00 1)"
  cron__remove "$id" >/dev/null
  run cat "$CRON_STORE"
  [[ "$output" == *"other-job"* ]]
}

@test "cron__remove_all: 全 CLAUDEOS エントリを削除" {
  cron__add ProjA 300 21:00 1 >/dev/null
  cron__add ProjB 120 08:00 2 >/dev/null
  run cron__remove_all
  [ "$output" -ge 2 ]
  run cron__list
  [ "$output" = "" ]
}

@test "cron__remove_all: 他人 cron は残す" {
  printf '%s\n' "0 5 * * * /usr/bin/other-job" > "$CRON_STORE"
  cron__add ProjA 300 21:00 1 >/dev/null
  cron__remove_all >/dev/null
  run cat "$CRON_STORE"
  [[ "$output" == *"other-job"* ]]
}

# --- cron__format_display ---

@test "cron__format_display: id/project/曜日/時刻/duration を整形" {
  run cron__format_display abc12345 MyProj 300 2026-06-01T10:00:00 "0 21 * * 1,6"
  [[ "$output" == *"[abc12345]"* ]]
  [[ "$output" == *"project=MyProj"* ]]
  [[ "$output" == *"月/土"* ]]
  [[ "$output" == *"21:00"* ]]
  [[ "$output" == *"300m"* ]]
}
