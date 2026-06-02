#!/usr/bin/env bash
# ============================================================
# monitor-sessions.sh — Cron/手動セッションのライブ監視タブ (ClaudeOS v3.3.8)
#
# 役割:
#   専用 tmux セッション "claudeos-monitor" を用意し、実行中の
#   claudeos-<project> セッションを link-window で「タブ(window)」として集約する。
#     - window 0 = ライブダッシュボード (既定1秒更新):
#                  経過時間 / 残り時間 / 実行中プロジェクト名を表示
#     - window 1.. = 各プロジェクト (Ctrl-b <n> で FG / Ctrl-b 0 で監視へ戻る)
#
# 経過/残りの算出 (ファイル I/O 不要・cron/手動を統一的に扱う):
#   経過 = now - #{session_created}                       (tmux が記録)
#   残り = @ccsu_duration_min*60 - 経過                   (起動時に仕込む user-option)
#   ※ @ccsu_project / @ccsu_duration_min は cron-launcher.sh / tmux-runner.sh が
#     セッション作成時にウィンドウ user-option として設定する。未設定でも経過のみ表示。
#
# サブコマンド:
#   open       (既定) claudeos-monitor を用意し attach (tmux 内なら switch-client)
#   dashboard  window 0 で動くライブループ本体 (open が内部起動)
#   sync       タブの link/unlink を1回だけ実行
#   --once     ダッシュボードを1回描画して終了 (非対話 / bats)
#   --help
#
# tmux は $TMUX_BIN (CCSU_TMUX_BIN) で差し替え可 (bats スタブ用)。
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

TMUX_BIN="${CCSU_TMUX_BIN:-tmux}"
MON_SESSION="${CCSU_MONITOR_SESSION:-claudeos-monitor}"
MON_REFRESH="${CCSU_MONITOR_REFRESH:-1}"     # ダッシュボード更新間隔 (秒)
MON_WARN_SEC="${CCSU_MONITOR_WARN_SEC:-300}" # 残りこの秒数以下で ⚠ 表示

# ------------------------------------------------------------
# 純粋ヘルパ (tmux 非依存・テスト対象)
# ------------------------------------------------------------

# mon__fmt_hms <seconds> — 秒を HH:MM:SS へ。負値/非数は 00:00:00 に丸める
mon__fmt_hms() {
  local s="${1:-0}"
  [[ "$s" =~ ^-?[0-9]+$ ]] || s=0
  (( s < 0 )) && s=0
  printf '%02d:%02d:%02d' $(( s / 3600 )) $(( (s % 3600) / 60 )) $(( s % 60 ))
}

# mon__status_icon <remaining_sec> <has_duration> — 状態アイコン
#   has_duration!=1: 残り不明 → ✽ / 残り<=0: ⏱(終了間近) / 残り<=WARN: ⚠ / それ以外: ✽
mon__status_icon() {
  local rem="${1:-0}" has="${2:-0}"
  [[ "$rem" =~ ^-?[0-9]+$ ]] || rem=0
  if [[ "$has" != "1" ]]; then printf '✽'; return 0; fi
  if   (( rem <= 0 ));            then printf '⏱'
  elif (( rem <= MON_WARN_SEC )); then printf '⚠'
  else                                printf '✽'
  fi
}

# ------------------------------------------------------------
# tmux 連携ヘルパ
# ------------------------------------------------------------

# mon__exists — claudeos-monitor が存在すれば 0
mon__exists() { "$TMUX_BIN" has-session -t "$MON_SESSION" 2>/dev/null; }

# mon__project_sessions — 実行中の claudeos-* (monitor / _keeper_ を除外) を1行1名で
mon__project_sessions() {
  "$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null \
    | grep '^claudeos-' | grep -vx "$MON_SESSION" || true
}

# mon__next_index — claudeos-monitor の次の空きウィンドウ index
mon__next_index() {
  local max
  max="$("$TMUX_BIN" list-windows -t "$MON_SESSION" -F '#{window_index}' 2>/dev/null | sort -n | tail -1)"
  printf '%d' $(( ${max:-0} + 1 ))
}

# mon__window_index_for <safe> — monitor 内で window_name==safe の index (無ければ空)
mon__window_index_for() {
  local safe="$1"
  mon__exists || return 0
  "$TMUX_BIN" list-windows -t "$MON_SESSION" -F '#{window_index} #{window_name}' 2>/dev/null \
    | awk -v n="$safe" '$2 == n { print $1; exit }'
}

# mon__sync_tabs — 実行中プロジェクトをタブとして link、消滅したタブを unlink
#   照合キーはウィンドウ名 (= safe project = claudeos-<safe> のサフィックス)。
#   ※ source セッション kill 後も link は残る (実機検証済) ため unlink が必須。
mon__sync_tabs() {
  mon__exists || return 0

  # --- 1) 未リンクのプロジェクトを追加 ---
  local names s safe ni
  names="$("$TMUX_BIN" list-windows -t "$MON_SESSION" -F '#{window_name}' 2>/dev/null || true)"
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    safe="${s#claudeos-}"
    if ! printf '%s\n' "$names" | grep -qxF "$safe"; then
      ni="$(mon__next_index)"
      if "$TMUX_BIN" link-window -s "${s}:0" -t "$MON_SESSION:$ni" 2>/dev/null; then
        # 安定名を付与 (link 後も次 tick で名前照合できるよう automatic-rename を切る)
        "$TMUX_BIN" set-option -w -t "$MON_SESSION:$ni" automatic-rename off 2>/dev/null || true
        "$TMUX_BIN" rename-window -t "$MON_SESSION:$ni" "$safe" 2>/dev/null || true
        names="$names"$'\n'"$safe"
      fi
    fi
  done < <(mon__project_sessions)

  # --- 2) source セッションが消えたタブを除去 (window 0=ダッシュボードは保持) ---
  local idx nm
  while read -r idx nm; do
    [[ -z "$idx" ]] && continue
    (( idx == 0 )) && continue
    [[ "$nm" == "monitor" ]] && continue
    if ! "$TMUX_BIN" has-session -t "claudeos-$nm" 2>/dev/null; then
      "$TMUX_BIN" unlink-window -k -t "$MON_SESSION:$idx" 2>/dev/null || true
    fi
  done < <("$TMUX_BIN" list-windows -t "$MON_SESSION" -F '#{window_index} #{window_name}' 2>/dev/null || true)
}

# mon__collect — 実行中セッションを「tab|project|elapsed|remaining|has_dur」で列挙
mon__collect() {
  local now s safe created dur proj elapsed rem has wn n=0
  now="$(date +%s)"
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    n=$(( n + 1 ))
    safe="${s#claudeos-}"
    created="$("$TMUX_BIN" display-message -p -t "$s" '#{session_created}' 2>/dev/null || true)"
    [[ "$created" =~ ^[0-9]+$ ]] || created="$now"
    dur="$("$TMUX_BIN" show-options -w -t "${s}:0" -qv @ccsu_duration_min 2>/dev/null || true)"
    proj="$("$TMUX_BIN" show-options -w -t "${s}:0" -qv @ccsu_project 2>/dev/null || true)"
    [[ -z "$proj" ]] && proj="$safe"
    elapsed=$(( now - created )); (( elapsed < 0 )) && elapsed=0
    if [[ "$dur" =~ ^[0-9]+$ ]]; then has=1; rem=$(( dur * 60 - elapsed )); else has=0; rem=0; fi
    wn="$(mon__window_index_for "$safe")"; [[ -z "$wn" ]] && wn="$n"
    printf '%s|%s|%s|%s|%s\n' "$wn" "$proj" "$elapsed" "$rem" "$has"
  done < <(mon__project_sessions)
}

# ------------------------------------------------------------
# 描画
# ------------------------------------------------------------
mon__hr() { printf '  %s%s%s\n' "$C_GRAY" "$(printf '─%.0s' {1..56})" "$C_RESET"; }

mon__render_once() {
  local stamp; stamp="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '\n  %s📺 ClaudeOS ライブ監視%s  (%s秒更新)        %s%s%s\n' \
    "$C_CYAN" "$C_RESET" "$MON_REFRESH" "$C_GRAY" "$stamp" "$C_RESET"
  mon__hr
  printf '   %s#  %-26s %-9s %-9s%s\n' "$C_GRAY" "プロジェクト" "経過" "残り" "$C_RESET"
  local any=0 tab proj el rem has ic rem_s
  while IFS='|' read -r tab proj el rem has; do
    [[ -z "$tab" ]] && continue
    any=1
    ic="$(mon__status_icon "$rem" "$has")"
    if [[ "$has" == "1" ]]; then rem_s="$(mon__fmt_hms "$rem")"; else rem_s="—"; fi
    printf '  %s%2s%s  %-26s %-9s %-9s %s\n' \
      "$C_YELLOW" "$tab" "$C_RESET" "$proj" "$(mon__fmt_hms "$el")" "$rem_s" "$ic"
  done < <(mon__collect)
  (( any == 0 )) && printf '   %s(実行中の ClaudeOS セッションなし)%s\n' "$C_GRAY" "$C_RESET"
  mon__hr
  printf '   %s[1-9]%s そのタブへ(FG)   %sCtrl-b 0%s 監視へ戻る   %s[r]%s更新 %s[q]%s終了\n' \
    "$C_GREEN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$C_RESET"
}

# mon__dashboard — window 0 で動くライブループ (open が内部起動)
mon__dashboard() {
  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true' EXIT
  local key
  while true; do
    mon__sync_tabs
    clear 2>/dev/null || true
    mon__render_once
    key=''
    read -rsn1 -t "$MON_REFRESH" key 2>/dev/null || true
    case "$key" in
      q|Q) break ;;
      [1-9]) "$TMUX_BIN" select-window -t "$MON_SESSION:$key" 2>/dev/null || true ;;
      *) : ;;   # r / 空(タイムアウト) → 再描画
    esac
  done
  tput cnorm 2>/dev/null || true
}

# mon__open — claudeos-monitor を用意して attach (tmux 内なら switch-client)
mon__open() {
  require_cmd "$TMUX_BIN" "tmux をインストールしてください (メニュー項7)"
  if ! mon__exists; then
    local self="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
    "$TMUX_BIN" new-session -d -s "$MON_SESSION" -n monitor -x 220 -y 50 \
      "bash '$self' dashboard" 2>/dev/null || { log_error "監視セッションを作成できませんでした"; return 1; }
    "$TMUX_BIN" set-option -w -t "$MON_SESSION:0" automatic-rename off 2>/dev/null || true
    "$TMUX_BIN" set-option -t "$MON_SESSION" mouse on 2>/dev/null || true
    log_ok "ライブ監視セッションを作成: $MON_SESSION"
  fi
  mon__sync_tabs
  if [[ -n "${TMUX:-}" ]]; then
    "$TMUX_BIN" switch-client -t "$MON_SESSION"
  else
    "$TMUX_BIN" attach -t "$MON_SESSION"
  fi
}

mon__usage() {
  cat <<'EOF'
Usage: monitor-sessions.sh [open|dashboard|sync|--once|--help]

  open       (既定) claudeos-monitor を用意し attach。実行中の各プロジェクトを
             タブ(window)として集約表示する。tmux 内からは switch-client。
  dashboard  window 0 のライブループ本体 (通常 open が内部起動)
  sync       タブの link/unlink を1回だけ実行
  --once     ダッシュボードを1回描画して終了 (非対話 / テスト)
  --help     このヘルプ

キー操作 (監視タブ表示中):
  [1-9]     その番号のプロジェクトタブへ切替 (フォアグラウンド)
  Ctrl-b 0  監視ダッシュボードへ戻る
  Ctrl-b n  次のタブ / Ctrl-b p 前のタブ (tmux 標準)
  [q]       監視ダッシュボードを終了 (各プロジェクトは BG で継続)
EOF
}

main() {
  case "${1:-open}" in
    open|"")        mon__open ;;
    dashboard)      mon__dashboard ;;
    sync)           mon__sync_tabs ;;
    --once|once)    mon__render_once ;;
    --help|-h)      mon__usage ;;
    *) log_error "不明な引数: $1"; mon__usage; return 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
