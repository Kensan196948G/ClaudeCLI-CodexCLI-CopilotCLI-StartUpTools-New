#!/usr/bin/env bash
# ============================================================
# tmux-runner.sh — ClaudeCode の tmux 実行エンジン (Linux native)
#
# 役割: 手動起動 (bin/start-claude.sh) から ClaudeCode を tmux セッションで
#       フォアグラウンド/バックグラウンド起動する。cron-launcher.sh と同じ
#       命名規則 (claudeos-<safe>) と pipe-pane ログ方式を共有するため、
#       メニュー項13(ログ監視)/項15(状態監視) が cron/手動どちらのセッションも
#       区別なく扱える。
#
# 移植元: Claude/templates/linux/cron-launcher.sh の tmux ブロック (L307-345)
#         + Start-ClaudeCode.ps1 のローカル起動 (SSH 分岐は廃止)
#
# 設計差分 (cron vs 手動):
#   - cron : keeper + wait-for で同期実行 (タイムアウト管理)
#   - 手動 : foreground=attach / background=detached で即復帰 (待たない)
# ============================================================

[[ -n "${_CCSU_TMUX_LOADED:-}" ]] && return 0
_CCSU_TMUX_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config-loader.sh"

# tmux/claude コマンド (テストでスタブ差し替え可)
TMUX_BIN="${CCSU_TMUX_BIN:-tmux}"
CLAUDE_BIN="${CCSU_CLAUDE_BIN:-claude}"

# tmux__session_name <project> — セッション名 (cron-launcher.sh と同一規則)
tmux__session_name() { printf 'claudeos-%s' "$(ccsu_safe_name "$1")"; }

# tmux__is_running <project> — 起動中なら 0
tmux__is_running() { "$TMUX_BIN" has-session -t "$(tmux__session_name "$1")" 2>/dev/null; }

# tmux__status — 全 claudeos-* セッションを列挙 (cron/手動 両方)
tmux__status() {
  local out
  out="$("$TMUX_BIN" ls 2>/dev/null | grep '^claudeos-' || true)"
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; else printf '(実行中の ClaudeOS セッションなし)\n'; fi
}

# tmux__attach <project> — セッションに接続
tmux__attach() {
  local s; s="$(tmux__session_name "$1")"
  tmux__is_running "$1" || { log_warn "セッションが見つかりません: $s"; return 1; }
  "$TMUX_BIN" attach -t "$s"
}

# tmux__stop <project> — セッションを停止 (keeper も落とす)
tmux__stop() {
  local safe s keeper
  safe="$(ccsu_safe_name "$1")"; s="claudeos-$safe"; keeper="_keeper_$safe"
  if "$TMUX_BIN" has-session -t "$s" 2>/dev/null; then
    "$TMUX_BIN" kill-session -t "$s" 2>/dev/null || true
    "$TMUX_BIN" kill-session -t "$keeper" 2>/dev/null || true
    log_ok "停止: $s"
  else
    log_warn "セッションが見つかりません: $s"
    return 1
  fi
}

# ------------------------------------------------------------
# tmux_run <project> <duration-min> <mode>
#   mode: foreground (既定, attach) | background (detached, 即復帰)
#   - PROJECTS_BASE/<project> に cd して tmux で claude を起動
#   - pipe-pane で TUI 制御シーケンス除去後のログを ~/.claudeos/logs へ
# ------------------------------------------------------------
tmux_run() {
  local project="$1" duration_min="${2:-300}" mode="${3:-foreground}"
  require_cmd "$TMUX_BIN"
  require_cmd "$CLAUDE_BIN"

  local safe session dur_sec base project_dir log_file stamp
  safe="$(ccsu_safe_name "$project")"
  session="claudeos-$safe"
  dur_sec=$((duration_min * 60))
  base="$(config_projects_dir)"
  project_dir="$base/$project"
  [[ -d "$project_dir" ]] || { log_error "プロジェクトディレクトリが存在しません: $project_dir"; return 1; }

  # 既に起動中なら再起動せず案内
  if "$TMUX_BIN" has-session -t "$session" 2>/dev/null; then
    log_warn "既に起動中です: $session"
    [[ "$mode" == "foreground" ]] && "$TMUX_BIN" attach -t "$session"
    return 0
  fi

  mkdir -p "$CCSU_HOME/logs"
  stamp="$(date +%Y%m%d-%H%M%S)"
  log_file="$CCSU_HOME/logs/manual-${stamp}-${safe}.log"

  # hooks 環境変数 (cron-launcher.sh L153 と同一)
  export CLAUDEOS_HOOKS_DIR="$project_dir/.claude/claudeos/scripts/hooks"
  export CLAUDE_PROJECT="$project"

  # START_PROMPT.md があれば claude に渡す (cat 展開を tmux コマンド内で実行)
  local claude_cmd
  if [[ -f "$project_dir/.claude/START_PROMPT.md" ]]; then
    claude_cmd="timeout ${dur_sec}s $CLAUDE_BIN --dangerously-skip-permissions \"\$(cat '$project_dir/.claude/START_PROMPT.md')\""
  else
    claude_cmd="timeout ${dur_sec}s $CLAUDE_BIN --dangerously-skip-permissions"
  fi

  # tmux セッション起動 (detached)。-c で作業ディレクトリ指定
  "$TMUX_BIN" new-session -d -s "$session" -c "$project_dir" -x 220 -y 50 "$claude_cmd"

  # pipe-pane: TUI 制御シーケンスを除去してログへ (cron-launcher.sh L333 と同一 sed)
  "$TMUX_BIN" pipe-pane -t "$session" -o \
    "sed 's/.*\r//; s/\x1b\][^\x07]*\x07//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b.//g' >> '$log_file'" 2>/dev/null || \
    log_warn "pipe-pane に失敗 (ログ可視化なし): $log_file"

  if [[ "$mode" == "foreground" ]]; then
    log_info "フォアグラウンド起動: $session (Ctrl-b d でデタッチしても BG 継続)"
    "$TMUX_BIN" attach -t "$session"
  else
    log_ok "バックグラウンド起動: $session"
    log_info "  接続: tmux attach -t $session"
    log_info "  停止: tmux kill-session -t $session"
    log_info "  ログ: $log_file"
  fi
}
