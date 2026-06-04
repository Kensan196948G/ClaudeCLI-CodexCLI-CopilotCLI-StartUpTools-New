#!/usr/bin/env bash
# ============================================================
# supervisor.sh — Autonomy Supervisor (Goal 到達まで自律再開) — ClaudeOS v3.4.0
#
# 役割:
#   登録プロジェクトの自律セッション (cron-launcher.sh) をセッション終了後に
#   再起動し、Goal/Release 到達 または ガードレール抵触まで「止まらない」自律を実現する。
#   各セッションは cron-launcher 経由なので TUI(claude) + resume header + メール + 監視タブ
#   メタデータをそのまま再利用する (自律エンジンを新規実装しない)。
#
# 停止条件 (いずれかで停止):
#   - Goal 到達 : project state.json の deploy.ready=true / phase_mode∈{maintenance,released}
#   - 異常      : kpi.security_critical>0 / blocked_issues 非空
#   - 上限      : 1日合計実行 >= daily_max_minutes / 再起動 >= max_restarts_per_day
#   - crash-loop: 極端に短いセッションが crash_loop_threshold 連続
#   - 手動      : stop フラグ / プロセス kill
#
# ガードレール既定値 (project state.json の "supervisor" ブロックで上書き可):
#   daily_max_minutes=600 / max_restarts_per_day=6 / session_minutes=300
#   cooldown_seconds=30 / crash_loop_threshold=3 / crash_loop_min_seconds=120
#
# テスト用 env 上書き:
#   CCSU_SUP_DIR           : 状態ディレクトリ      (既定 $CCSU_HOME/supervisor)
#   CCSU_SUP_CRON_LAUNCHER : cron-launcher.sh パス (既定 ~/.claudeos/cron-launcher.sh)
#   CCSU_SUP_TODAY         : 当日 (YYYY-MM-DD)     (日次リセット検証用)
#   CCSU_SUP_COOLDOWN      : クールダウン秒上書き  (テストは 0)
#   CCSU_TMUX_BIN          : tmux コマンド         (--now 停止時のセッション kill)
# ============================================================

[[ -n "${_CCSU_SUPERVISOR_LOADED:-}" ]] && return 0
_CCSU_SUPERVISOR_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/json.sh"

SUP_DIR="${CCSU_SUP_DIR:-$CCSU_HOME/supervisor}"
SUP_CRON_LAUNCHER="${CCSU_SUP_CRON_LAUNCHER:-$HOME/.claudeos/cron-launcher.sh}"
SUP_TMUX_BIN="${CCSU_TMUX_BIN:-tmux}"

# ガードレール既定値
SUP_DEF_DAILY_MAX_MIN=600
SUP_DEF_MAX_RESTARTS=6
SUP_DEF_SESSION_MIN=300
SUP_DEF_COOLDOWN=30
SUP_DEF_CRASH_THRESHOLD=3
SUP_DEF_CRASH_MIN_SEC=120

# ------------------------------------------------------------
# パス/基本ヘルパ
# ------------------------------------------------------------
sup__state_file() { printf '%s/%s.json' "$SUP_DIR" "$(ccsu_safe_name "$1")"; }
sup__stop_file()  { printf '%s/%s.stop' "$SUP_DIR" "$(ccsu_safe_name "$1")"; }
sup__today()      { printf '%s' "${CCSU_SUP_TODAY:-$(date +%Y-%m-%d)}"; }
sup__now_iso()    { date -Iseconds; }

# sup__guard <project_state_json> <key> <default> — supervisor 設定値を取得
sup__guard() {
  local pstate="$1" key="$2" def="$3" v=""
  [[ -f "$pstate" ]] && v="$(json_get "$pstate" ".supervisor.$key" "")"
  [[ "$v" =~ ^[0-9]+$ ]] && printf '%s' "$v" || printf '%s' "$def"
}

# ------------------------------------------------------------
# 純粋ガードレール判定 (引数 in / 理由文字列 out。空 = 継続)
# ------------------------------------------------------------

# sup__goal_reason <deploy_ready> <phase_mode>
sup__goal_reason() {
  local ready="$1" mode="$2"
  [[ "$ready" == "true" ]] && { printf 'goal-reached:deploy.ready'; return 0; }
  case "$mode" in
    maintenance|released) printf 'goal-reached:phase_mode=%s' "$mode" ;;
    *) : ;;
  esac
}

# sup__abnormal_reason <security_critical> <blocked_count>
sup__abnormal_reason() {
  local sec="${1:-0}" blocked="${2:-0}"
  [[ "$sec" =~ ^[0-9]+$ ]] || sec=0
  [[ "$blocked" =~ ^[0-9]+$ ]] || blocked=0
  if   (( sec > 0 ));     then printf 'blocked:security_critical=%s' "$sec"
  elif (( blocked > 0 )); then printf 'blocked:blocked_issues=%s' "$blocked"
  fi
}

# sup__cap_reason <minutes_today> <daily_max> <restarts_today> <max_restarts>
sup__cap_reason() {
  local min="${1:-0}" dmax="${2:-0}" rst="${3:-0}" rmax="${4:-0}"
  if   (( dmax > 0 && min >= dmax )); then printf 'daily-cap:minutes=%s/%s' "$min" "$dmax"
  elif (( rmax > 0 && rst >= rmax )); then printf 'daily-cap:restarts=%s/%s' "$rst" "$rmax"
  fi
}

# sup__crash_reason <consecutive_short> <threshold>
sup__crash_reason() {
  local cs="${1:-0}" th="${2:-3}"
  (( th > 0 && cs >= th )) && printf 'crash-loop:short_sessions=%s' "$cs"
}

# sup__project_stop_reason <project_state_json> — 到達/異常を集約 (空=継続)
sup__project_stop_reason() {
  local pstate="$1" ready mode sec blocked reason
  [[ -f "$pstate" ]] || return 0
  ready="$(json_get "$pstate" '.deploy.ready' 'false')"
  mode="$(json_get "$pstate" '.project.phase_mode' '')"
  [[ -z "$mode" ]] && mode="$(json_get "$pstate" '.maintenance.phase_mode' '')"
  sec="$(json_get "$pstate" '.kpi.security_critical' '0')"
  blocked="$(json_get "$pstate" '.blocked_issues | length' '0')"
  reason="$(sup__goal_reason "$ready" "$mode")"; [[ -n "$reason" ]] && { printf '%s' "$reason"; return 0; }
  reason="$(sup__abnormal_reason "$sec" "$blocked")"; [[ -n "$reason" ]] && { printf '%s' "$reason"; return 0; }
}

# ------------------------------------------------------------
# supervisor 状態ファイル I/O (フラット JSON。SUP_* 作業変数を書き出す)
# ------------------------------------------------------------
sup__persist() {
  local project="$1" f tmp ended_json="null"
  f="$(sup__state_file "$project")"
  mkdir -p "$SUP_DIR"; chmod 700 "$SUP_DIR" 2>/dev/null || true
  [[ -n "${SUP_ENDED_AT:-}" ]] && ended_json="\"$SUP_ENDED_AT\""
  tmp="$f.tmp.$$"
  cat > "$tmp" <<JSON
{
  "project": "$project",
  "status": "${SUP_STATUS:-running}",
  "pid": ${SUP_PID:-0},
  "started_at": "${SUP_STARTED_AT:-}",
  "ended_at": ${ended_json},
  "day": "${SUP_DAY:-}",
  "restarts_today": ${SUP_RESTARTS:-0},
  "minutes_today": ${SUP_MINUTES:-0},
  "consecutive_short": ${SUP_CONSEC_SHORT:-0},
  "last_session_secs": ${SUP_LAST_SECS:-0},
  "last_reason": "${SUP_LAST_REASON:-}",
  "updated_at": "$(sup__now_iso)"
}
JSON
  mv "$tmp" "$f"
}

# sup__get <project> <field> <default> — 状態フィールド読取
sup__get() {
  local f; f="$(sup__state_file "$1")"
  [[ -f "$f" ]] || { printf '%s' "$3"; return 0; }
  json_get "$f" ".$2" "$3"
}

# sup__is_running <project> — pid 生存かつ status=running なら 0
sup__is_running() {
  local f pid status; f="$(sup__state_file "$1")"
  [[ -f "$f" ]] || return 1
  status="$(json_get "$f" '.status' '')"
  pid="$(json_get "$f" '.pid' '0')"
  [[ "$status" == "running" ]] || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )) || return 1
  kill -0 "$pid" 2>/dev/null
}

# sup__request_stop <project> — グレースフル停止フラグ
sup__request_stop() {
  mkdir -p "$SUP_DIR"
  : > "$(sup__stop_file "$1")"
}

# ------------------------------------------------------------
# sup__sleep <seconds> — stop フラグを見ながら中断可能スリープ (テストは即時)
# ------------------------------------------------------------
sup__sleep() {
  local project="$1" secs="$2" i
  (( secs <= 0 )) && return 0
  for ((i = 0; i < secs; i++)); do
    [[ -f "$(sup__stop_file "$project")" ]] && return 0
    sleep 1
  done
}

# ------------------------------------------------------------
# sup__loop <project> [duration_min] — supervisor 本体 (setsid から実行)
# ------------------------------------------------------------
sup__loop() {
  local project="$1" duration="${2:-}"
  local safe base project_dir pstate
  safe="$(ccsu_safe_name "$project")"
  base="$(json_get "$CCSU_CONFIG_PATH" '.projects' "$HOME/Projects")"
  project_dir="$base/$project"
  pstate="$project_dir/state.json"

  # ガードレール値 (project state.json で上書き可)
  local daily_max max_restarts session_min cooldown crash_th crash_min
  daily_max="$(sup__guard "$pstate" daily_max_minutes "$SUP_DEF_DAILY_MAX_MIN")"
  max_restarts="$(sup__guard "$pstate" max_restarts_per_day "$SUP_DEF_MAX_RESTARTS")"
  session_min="${duration:-$(sup__guard "$pstate" session_minutes "$SUP_DEF_SESSION_MIN")}"
  cooldown="${CCSU_SUP_COOLDOWN:-$(sup__guard "$pstate" cooldown_seconds "$SUP_DEF_COOLDOWN")}"
  crash_th="$(sup__guard "$pstate" crash_loop_threshold "$SUP_DEF_CRASH_THRESHOLD")"
  crash_min="$(sup__guard "$pstate" crash_loop_min_seconds "$SUP_DEF_CRASH_MIN_SEC")"

  # 作業変数 (SUP_* グローバル: sup__persist が書き出す)
  SUP_PID=$$; SUP_STATUS=running; SUP_STARTED_AT="$(sup__now_iso)"; SUP_ENDED_AT=""
  SUP_DAY="$(sup__today)"; SUP_RESTARTS=0; SUP_MINUTES=0; SUP_CONSEC_SHORT=0
  SUP_LAST_SECS=0; SUP_LAST_REASON=""
  # 注: stop フラグのクリアは呼び出し側 (au__start) が起動前に行う。
  #     ここでクリアしないことで、起動前/実行中に立てたフラグを確実に拾える。
  sup__persist "$project"
  log_info "[supervisor] start: $project (daily_max=${daily_max}m restarts=${max_restarts} session=${session_min}m)"

  local stop_reason="" sess_start sess_end sess_secs
  while true; do
    # 1) 手動停止
    if [[ -f "$(sup__stop_file "$project")" ]]; then stop_reason="stopped:manual"; break; fi
    # 2) 日次リセット
    if [[ "$SUP_DAY" != "$(sup__today)" ]]; then
      SUP_DAY="$(sup__today)"; SUP_RESTARTS=0; SUP_MINUTES=0; SUP_CONSEC_SHORT=0
    fi
    # 3) Goal/異常 (セッション前)
    stop_reason="$(sup__project_stop_reason "$pstate")"; [[ -n "$stop_reason" ]] && break
    # 4) 日次上限
    stop_reason="$(sup__cap_reason "$SUP_MINUTES" "$daily_max" "$SUP_RESTARTS" "$max_restarts")"; [[ -n "$stop_reason" ]] && break
    # 5) crash-loop
    stop_reason="$(sup__crash_reason "$SUP_CONSEC_SHORT" "$crash_th")"; [[ -n "$stop_reason" ]] && break

    # 6) 1 セッション実行 (cron-launcher がセッション終了までブロック)
    if [[ ! -f "$SUP_CRON_LAUNCHER" ]]; then stop_reason="stopped:launcher-missing"; break; fi
    SUP_STATUS=running; SUP_LAST_REASON="launching session"; sup__persist "$project"
    sess_start="$(date +%s)"
    bash "$SUP_CRON_LAUNCHER" "$project" "$session_min" || true
    sess_end="$(date +%s)"; sess_secs=$(( sess_end - sess_start )); (( sess_secs < 0 )) && sess_secs=0

    # 7) カウンタ更新
    SUP_RESTARTS=$(( SUP_RESTARTS + 1 ))
    SUP_MINUTES=$(( SUP_MINUTES + sess_secs / 60 ))
    SUP_LAST_SECS="$sess_secs"
    if (( sess_secs < crash_min )); then SUP_CONSEC_SHORT=$(( SUP_CONSEC_SHORT + 1 )); else SUP_CONSEC_SHORT=0; fi
    SUP_LAST_REASON="session ended (${sess_secs}s)"; sup__persist "$project"

    # 8) Goal/異常 (セッション後)
    stop_reason="$(sup__project_stop_reason "$pstate")"; [[ -n "$stop_reason" ]] && break

    # 9) クールダウン
    sup__sleep "$project" "$cooldown"
  done

  # 終了処理
  case "$stop_reason" in
    goal-reached:*) SUP_STATUS="goal-reached" ;;
    blocked:*)      SUP_STATUS="blocked" ;;
    crash-loop:*)   SUP_STATUS="crash-loop" ;;
    daily-cap:*)    SUP_STATUS="daily-cap" ;;
    *)              SUP_STATUS="stopped" ;;
  esac
  SUP_LAST_REASON="$stop_reason"; SUP_ENDED_AT="$(sup__now_iso)"
  sup__persist "$project"
  rm -f "$(sup__stop_file "$project")"
  log_info "[supervisor] stop: $project → status=$SUP_STATUS reason=$stop_reason restarts=$SUP_RESTARTS minutes=$SUP_MINUTES"
}
