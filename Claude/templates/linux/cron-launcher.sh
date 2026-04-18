#!/usr/bin/env bash
# ============================================================
# cron-launcher.sh - Linux 側で ClaudeCode を cron から起動するラッパ
# ClaudeOS v3.2.31
#
# Usage: cron-launcher.sh <project> <duration-minutes>
#
# 責務:
#   - /home/kensan/Projects/<project> に cd
#   - timeout <Ns> 付きで claude を起動（auto mode）
#   - session.json の生成・更新（start/end/status）
#   - ログを /home/kensan/.claudeos/logs/ へ
#   - 終了時に HTML レポートメールを送信 (v3.2.0 追加)
# ============================================================

set -euo pipefail

PROJECT="${1:-}"
DURATION_MIN="${2:-300}"

if [[ -z "$PROJECT" ]]; then
  echo "[ERROR] project 引数がありません" >&2
  echo "Usage: $0 <project> <duration-minutes>" >&2
  exit 2
fi

CLAUDEOS_HOME="${CLAUDEOS_HOME:-$HOME/.claudeos}"
SESSIONS_DIR="$CLAUDEOS_HOME/sessions"
LOGS_DIR="$CLAUDEOS_HOME/logs"
PROJECTS_BASE="${PROJECTS_BASE:-$HOME/Projects}"
PROJECT_DIR="$PROJECTS_BASE/$PROJECT"
REPORT_SCRIPT="${CLAUDEOS_REPORT_SCRIPT:-$CLAUDEOS_HOME/report-and-mail.py}"

mkdir -p "$SESSIONS_DIR" "$LOGS_DIR"
chmod 700 "$CLAUDEOS_HOME" "$SESSIONS_DIR" "$LOGS_DIR" 2>/dev/null || true

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "[ERROR] プロジェクトディレクトリが存在しません: $PROJECT_DIR" >&2
  exit 3
fi

DURATION_SEC=$((DURATION_MIN * 60))
SAFE_PROJECT=$(echo "$PROJECT" | tr -c 'A-Za-z0-9_-' '_')
STAMP=$(date +'%Y%m%d-%H%M%S')
SESSION_ID="${STAMP}-${SAFE_PROJECT}"
SESSION_FILE="$SESSIONS_DIR/${SESSION_ID}.json"
LOG_FILE="$LOGS_DIR/cron-${STAMP}.log"

START_TIME=$(date -Iseconds)
END_TIME_PLANNED=$(date -Iseconds -d "+${DURATION_MIN} minutes")

# --- session.json を初期化 ---
cat > "$SESSION_FILE.tmp" <<EOF
{
  "sessionId": "$SESSION_ID",
  "project": "$PROJECT",
  "trigger": "cron",
  "start_time": "$START_TIME",
  "max_duration_minutes": $DURATION_MIN,
  "end_time_planned": "$END_TIME_PLANNED",
  "status": "running",
  "pid": $$,
  "last_updated": "$START_TIME"
}
EOF
mv "$SESSION_FILE.tmp" "$SESSION_FILE"

TMUX_SESSION="claudeos-${SAFE_PROJECT}"
CLAUDE_EXIT_FILE="$SESSIONS_DIR/${SESSION_ID}.exit"
CLAUDE_WRAPPER="$SESSIONS_DIR/${SESSION_ID}.wrapper.sh"

# 終了時に status を更新するトラップ
finalize() {
  local exit_code=$?
  local final_status="completed"
  if [[ $exit_code -eq 124 ]]; then
    # timeout による終了
    final_status="timeout"
  elif [[ $exit_code -ne 0 ]]; then
    final_status="failed"
  fi
  local now
  now=$(date -Iseconds)

  if [[ -f "$SESSION_FILE" ]]; then
    # jq があればそれで、無ければ sed で status と last_updated を書き換える
    if command -v jq >/dev/null 2>&1; then
      jq --arg s "$final_status" --arg t "$now" \
        '.status = $s | .last_updated = $t' "$SESSION_FILE" > "$SESSION_FILE.tmp" \
        && mv "$SESSION_FILE.tmp" "$SESSION_FILE"
    else
      sed -i \
        -e "s/\"status\": \"running\"/\"status\": \"$final_status\"/" \
        -e "s/\"last_updated\": \"[^\"]*\"/\"last_updated\": \"$now\"/" \
        "$SESSION_FILE"
    fi
  fi

  echo "[cron-launcher] session finished status=$final_status exit=$exit_code at $now" >> "$LOG_FILE"

  # tmux セッションを終了・一時ファイルを削除
  if command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t "claudeos-${SAFE_PROJECT}" 2>/dev/null || true
  fi
  rm -f "$CLAUDE_WRAPPER" "$CLAUDE_EXIT_FILE" "${CLAUDE_WRAPPER%.sh}.prompt"

  # --- v3.2.0: HTML レポートメール送信 ---
  # 明示的トグル CLAUDEOS_EMAIL_ENABLED=1 が必要。誤送信防止のため既定 off。
  # 加えて python3 とスクリプトの存在も確認 (best-effort、失敗しても全体は成功扱い)。
  local email_enabled="${CLAUDEOS_EMAIL_ENABLED:-0}"
  if [[ "$email_enabled" != "1" ]]; then
    echo "[cron-launcher] HTML mail report skip (CLAUDEOS_EMAIL_ENABLED!=1)" >> "$LOG_FILE"
  elif command -v python3 >/dev/null 2>&1 && [[ -f "$REPORT_SCRIPT" ]]; then
    python3 "$REPORT_SCRIPT" \
      --session "$SESSION_ID" \
      --log "$LOG_FILE" \
      --status "$final_status" \
      --start "$START_TIME" \
      --end "$now" \
      --duration-min "$DURATION_MIN" \
      --project "$PROJECT" \
      --sessions-dir "$SESSIONS_DIR" \
      >> "$LOG_FILE" 2>&1 || true
  else
    echo "[cron-launcher] report-and-mail.py をスキップ (script=$REPORT_SCRIPT, python3=$(command -v python3 || echo 'none'))" >> "$LOG_FILE"
  fi
}
trap finalize EXIT

echo "[cron-launcher] $(date -Iseconds) project=$PROJECT duration=${DURATION_MIN}m session=$SESSION_ID" | tee -a "$LOG_FILE"

cd "$PROJECT_DIR"

export LANG=C.UTF-8 LC_ALL=C.UTF-8
export CLAUDE_SESSION_ID="$SESSION_ID"
export CLAUDE_PROJECT="$PROJECT"

# START_PROMPT.md が存在すれば引数として渡し、ClaudeCode を auto mode で起動
PROMPT_ARG=""
if [[ -f "$PROJECT_DIR/.claude/START_PROMPT.md" ]]; then
  PROMPT_ARG="$(cat "$PROJECT_DIR/.claude/START_PROMPT.md")"
fi

# PROMPT_ARG をサイドカーファイルへ書き出す（tmux env var 継承バグ / 長大引数問題を回避）
PROMPT_FILE="${CLAUDE_WRAPPER%.sh}.prompt"
printf '%s' "$PROMPT_ARG" > "$PROMPT_FILE"

# wrapper script: -e フラグ経由で env var を渡す（tmux サーバーのグローバル環境に依存しない）
# set -e を使わず claude_exit に明示的に格納する（非0終了でも wait-for -S を必ず実行するため）
cat > "$CLAUDE_WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
claude_exit=0
_prompt_file="${_CLAUDEOS_PROMPT_FILE:-}"
if [[ -f "$_prompt_file" ]] && [[ -s "$_prompt_file" ]]; then
  _prompt_content="$(cat "$_prompt_file")"
  timeout --foreground "${_CLAUDEOS_DURATION_SEC}s" claude --dangerously-skip-permissions "$_prompt_content" || claude_exit=$?
else
  timeout --foreground "${_CLAUDEOS_DURATION_SEC}s" claude --dangerously-skip-permissions || claude_exit=$?
fi
echo "$claude_exit" > "${_CLAUDEOS_EXIT_FILE}"
# 終了コード書き込み後に親 shell へ通知（失敗時もここまで必ず到達する）
tmux wait-for -S "${_CLAUDEOS_TMUX_DONE}"
WRAPPER_EOF
chmod +x "$CLAUDE_WRAPPER"

_TMUX_DONE="done-${SAFE_PROJECT}"

if command -v tmux >/dev/null 2>&1 && [[ "${CLAUDEOS_TMUX:-1}" == "1" ]]; then
  # Claude を tmux セッション内で起動（TTY あり → attach で UI 閲覧可能）
  # -e で env var を明示渡し（tmux サーバーのグローバル環境に依存しない）
  tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
  tmux new-session -d -s "$TMUX_SESSION" -x 220 -y 50 \
    -e "_CLAUDEOS_DURATION_SEC=$DURATION_SEC" \
    -e "_CLAUDEOS_EXIT_FILE=$CLAUDE_EXIT_FILE" \
    -e "_CLAUDEOS_TMUX_DONE=$_TMUX_DONE" \
    -e "_CLAUDEOS_PROMPT_FILE=$PROMPT_FILE" \
    "$CLAUDE_WRAPPER"
  echo "[cron-launcher] tmux attach -t $TMUX_SESSION  (UI閲覧用)" >> "$LOG_FILE"
  # tmux セッション終了まで待機
  tmux wait-for "$_TMUX_DONE"
else
  # tmux 無効時は従来通り TTY なし実行
  timeout --foreground "${DURATION_SEC}s" claude --dangerously-skip-permissions ${PROMPT_ARG:+"$PROMPT_ARG"} >> "$LOG_FILE" 2>&1
fi

# wrapper が書いた終了コードを読み取り、EXIT トラップへ伝播
if [[ -f "$CLAUDE_EXIT_FILE" ]]; then
  CLAUDE_EXIT=$(cat "$CLAUDE_EXIT_FILE")
  if [[ "$CLAUDE_EXIT" != "0" ]]; then
    exit "${CLAUDE_EXIT}"
  fi
fi
