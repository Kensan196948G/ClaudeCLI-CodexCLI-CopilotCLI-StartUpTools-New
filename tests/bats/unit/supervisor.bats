#!/usr/bin/env bats
# ============================================================
# supervisor.bats — lib/supervisor.sh のユニットテスト
#   ガードレール純粋関数 / 状態I/O / ループ各停止シナリオを検証。
#   cron-launcher は stub、停止は state.json/上限/フラグで誘発。
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  export AI_STARTUP_CONFIG_PATH="$TEST_TEMP/config.json"
  printf '{ "projects": "%s/projects" }\n' "$TEST_TEMP" > "$AI_STARTUP_CONFIG_PATH"
  export CCSU_SUP_DIR="$TEST_TEMP/sup"
  export CCSU_SUP_COOLDOWN=0
  export CCSU_SUP_CRON_LAUNCHER="$TEST_TEMP/launcher.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CCSU_SUP_CRON_LAUNCHER"; chmod +x "$CCSU_SUP_CRON_LAUNCHER"
  mkdir -p "$TEST_TEMP/projects/Demo"
  source "$REPO_ROOT/lib/supervisor.sh"
}
teardown() { _bats_common_teardown; }

# ---- 純粋ガードレール関数 ----------------------------------
@test "sup__goal_reason: deploy.ready=true" { run sup__goal_reason true development; [ "$output" = "goal-reached:deploy.ready" ]; }
@test "sup__goal_reason: phase_mode=maintenance" { run sup__goal_reason false maintenance; [ "$output" = "goal-reached:phase_mode=maintenance" ]; }
@test "sup__goal_reason: released" { run sup__goal_reason false released; [ "$output" = "goal-reached:phase_mode=released" ]; }
@test "sup__goal_reason: development は継続(空)" { run sup__goal_reason false development; [ -z "$output" ]; }
@test "sup__abnormal_reason: security>0" { run sup__abnormal_reason 2 0; [ "$output" = "blocked:security_critical=2" ]; }
@test "sup__abnormal_reason: blocked>0" { run sup__abnormal_reason 0 3; [ "$output" = "blocked:blocked_issues=3" ]; }
@test "sup__abnormal_reason: 正常は空" { run sup__abnormal_reason 0 0; [ -z "$output" ]; }
@test "sup__cap_reason: minutes 到達" { run sup__cap_reason 600 600 0 6; [[ "$output" == daily-cap:minutes* ]]; }
@test "sup__cap_reason: restarts 到達" { run sup__cap_reason 0 600 6 6; [[ "$output" == daily-cap:restarts* ]]; }
@test "sup__cap_reason: 上限内は空" { run sup__cap_reason 10 600 1 6; [ -z "$output" ]; }
@test "sup__crash_reason: 閾値到達" { run sup__crash_reason 3 3; [[ "$output" == crash-loop* ]]; }
@test "sup__crash_reason: 閾値未満は空" { run sup__crash_reason 1 3; [ -z "$output" ]; }

# ---- project state.json 読取判定 ---------------------------
@test "sup__project_stop_reason: deploy.ready=true → goal-reached" {
  echo '{ "deploy": {"ready": true} }' > "$TEST_TEMP/p.json"
  run sup__project_stop_reason "$TEST_TEMP/p.json"
  [ "$output" = "goal-reached:deploy.ready" ]
}
@test "sup__project_stop_reason: phase_mode=maintenance → goal-reached" {
  echo '{ "project": {"phase_mode":"maintenance"} }' > "$TEST_TEMP/p.json"
  run sup__project_stop_reason "$TEST_TEMP/p.json"
  [ "$output" = "goal-reached:phase_mode=maintenance" ]
}
@test "sup__project_stop_reason: development は空(継続)" {
  echo '{ "project": {"phase_mode":"development"}, "deploy": {"ready": false} }' > "$TEST_TEMP/p.json"
  run sup__project_stop_reason "$TEST_TEMP/p.json"
  [ -z "$output" ]
}
@test "sup__project_stop_reason: blocked_issues 非空 → blocked" {
  echo '{ "deploy": {"ready": false}, "blocked_issues": [101,102] }' > "$TEST_TEMP/p.json"
  run sup__project_stop_reason "$TEST_TEMP/p.json"
  [ "$output" = "blocked:blocked_issues=2" ]
}

# ---- 状態 I/O ----------------------------------------------
@test "sup__persist + sup__get: 往復し妥当な JSON" {
  SUP_STATUS=running SUP_PID=$$ SUP_RESTARTS=2 SUP_MINUTES=42 sup__persist Demo
  [ "$(sup__get Demo status '')" = "running" ]
  [ "$(sup__get Demo restarts_today 0)" = "2" ]
  [ "$(sup__get Demo minutes_today 0)" = "42" ]
  jq -e . "$CCSU_SUP_DIR/Demo.json" >/dev/null
}
@test "sup__is_running: 生存pid+running なら 0" {
  SUP_STATUS=running SUP_PID=$$ sup__persist Demo
  run sup__is_running Demo; [ "$status" -eq 0 ]
}
@test "sup__is_running: 死pid なら非0" {
  SUP_STATUS=running SUP_PID=999999 sup__persist Demo
  run sup__is_running Demo; [ "$status" -ne 0 ]
}
@test "sup__is_running: status!=running なら非0" {
  SUP_STATUS=stopped SUP_PID=$$ sup__persist Demo
  run sup__is_running Demo; [ "$status" -ne 0 ]
}
@test "sup__request_stop: stop フラグを作成" {
  sup__request_stop Demo
  [ -f "$CCSU_SUP_DIR/Demo.stop" ]
}

# ---- ループ各停止シナリオ ----------------------------------
@test "sup__loop: deploy.ready=true で goal-reached 即停止 (restarts=0)" {
  echo '{ "deploy": {"ready": true} }' > "$TEST_TEMP/projects/Demo/state.json"
  run sup__loop Demo 5
  [ "$status" -eq 0 ]
  [ "$(sup__get Demo status '')" = "goal-reached" ]
  [ "$(sup__get Demo restarts_today 0)" = "0" ]
}
@test "sup__loop: max_restarts=1 で 1セッション後 daily-cap" {
  echo '{ "deploy": {"ready": false}, "supervisor": {"max_restarts_per_day": 1, "crash_loop_min_seconds": 0} }' > "$TEST_TEMP/projects/Demo/state.json"
  run sup__loop Demo 5
  [ "$(sup__get Demo status '')" = "daily-cap" ]
  [ "$(sup__get Demo restarts_today 0)" = "1" ]
}
@test "sup__loop: 短命連続で crash-loop 停止" {
  echo '{ "deploy": {"ready": false}, "supervisor": {"crash_loop_threshold": 2, "crash_loop_min_seconds": 999999, "max_restarts_per_day": 100} }' > "$TEST_TEMP/projects/Demo/state.json"
  run sup__loop Demo 5
  [ "$(sup__get Demo status '')" = "crash-loop" ]
}
@test "sup__loop: 起動前 stop フラグで manual 停止 (restarts=0)" {
  echo '{ "deploy": {"ready": false} }' > "$TEST_TEMP/projects/Demo/state.json"
  mkdir -p "$CCSU_SUP_DIR"; : > "$CCSU_SUP_DIR/Demo.stop"
  run sup__loop Demo 5
  [ "$(sup__get Demo status '')" = "stopped" ]
  [ "$(sup__get Demo restarts_today 0)" = "0" ]
}
@test "sup__loop: launcher 不在で停止 (暴走しない)" {
  echo '{ "deploy": {"ready": false} }' > "$TEST_TEMP/projects/Demo/state.json"
  SUP_CRON_LAUNCHER="$TEST_TEMP/does-not-exist.sh"
  run sup__loop Demo 5
  [ "$(sup__get Demo status '')" = "stopped" ]
  [ "$(sup__get Demo restarts_today 0)" = "0" ]
}

@test "sup__loop: 再起動ループ中に deploy.ready 反転で goal-reached (E2E)" {
  # cron-launcher stub: 2回目の呼び出しで project state.json の deploy.ready を true に
  cat > "$CCSU_SUP_CRON_LAUNCHER" <<EOF
#!/usr/bin/env bash
c="$TEST_TEMP/count"; n=\$(( \$(cat "\$c" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "\$c"
if (( n >= 2 )); then echo '{ "deploy": {"ready": true} }' > "$TEST_TEMP/projects/Demo/state.json"; fi
exit 0
EOF
  chmod +x "$CCSU_SUP_CRON_LAUNCHER"
  echo '{ "deploy": {"ready": false}, "supervisor": {"crash_loop_min_seconds": 0, "max_restarts_per_day": 100} }' > "$TEST_TEMP/projects/Demo/state.json"
  run sup__loop Demo 5
  # 2 セッション走って 2 回目後に goal 検出 → 停止
  [ "$(sup__get Demo status '')" = "goal-reached" ]
  [ "$(sup__get Demo restarts_today 0)" = "2" ]
}
