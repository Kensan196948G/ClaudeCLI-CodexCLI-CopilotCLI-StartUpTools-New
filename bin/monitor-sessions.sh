#!/usr/bin/env bash
# ============================================================
# monitor-sessions.sh — ライブ監視タブ + 統合コントロールセンター (ClaudeOS v3.4.3)
#   (Phase 2: 登録プロジェクト一覧 + supervisor 起動/停止/介入を 1 画面に統合)
#   (v3.4.3: n キーで全プロジェクトから選んで自律管理に追加するオンボード)
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
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"
# shellcheck source=lib/cron-manager.sh
source "$SCRIPT_DIR/../lib/cron-manager.sh"
# shellcheck source=lib/supervisor.sh
source "$SCRIPT_DIR/../lib/supervisor.sh"

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

# mon__sync_tabs — 実行中プロジェクトをタブとして link、不要/重複タブを unlink
#   照合キーは window_id (#{window_id})。リンク元と共有され、リネームやセッション
#   再生成に影響されないため、名前ベースで起きていた二重リンクを防げる。
mon__sync_tabs() {
  mon__exists || return 0

  # 有効な source の window_id 集合 (= 実行中プロジェクトの window 0)
  local valid_wids s wid
  valid_wids="$(
    while IFS= read -r s; do
      [[ -z "$s" ]] && continue
      "$TMUX_BIN" display-message -p -t "${s}:0" '#{window_id}' 2>/dev/null || true
    done < <(mon__project_sessions)
  )"

  # --- 1) 未リンクのプロジェクトを追加 (window_id で照合) ---
  local mon_wids ni
  mon_wids="$("$TMUX_BIN" list-windows -t "$MON_SESSION" -F '#{window_id}' 2>/dev/null || true)"
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    wid="$("$TMUX_BIN" display-message -p -t "${s}:0" '#{window_id}' 2>/dev/null || true)"
    [[ -z "$wid" ]] && continue
    if ! printf '%s\n' "$mon_wids" | grep -qxF "$wid"; then
      ni="$(mon__next_index)"
      if "$TMUX_BIN" link-window -s "${s}:0" -t "$MON_SESSION:$ni" 2>/dev/null; then
        "$TMUX_BIN" set-option -w -t "$MON_SESSION:$ni" automatic-rename off 2>/dev/null || true
        "$TMUX_BIN" rename-window -t "$MON_SESSION:$ni" "${s#claudeos-}" 2>/dev/null || true
        mon_wids="$mon_wids"$'\n'"$wid"
      fi
    fi
  done < <(mon__project_sessions)

  # --- 2) 不要/重複タブを除去 (dashboard=window名 monitor は常に保持) ---
  #   無効な window_id (source 消滅) または既出 (重複リンク) を unlink。
  local idx w nm seen=""
  while read -r idx w nm; do
    [[ -z "$idx" ]] && continue
    (( idx == 0 )) && continue
    [[ "$nm" == "monitor" ]] && continue
    if ! printf '%s\n' "$valid_wids" | grep -qxF "$w" || printf '%s\n' "$seen" | grep -qxF "$w"; then
      "$TMUX_BIN" unlink-window -k -t "$MON_SESSION:$idx" 2>/dev/null || true
    else
      seen="$seen"$'\n'"$w"
    fi
  done < <("$TMUX_BIN" list-windows -t "$MON_SESSION" -F '#{window_index} #{window_id} #{window_name}' 2>/dev/null || true)
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
# 登録プロジェクト + supervisor (コントロールセンター)
# ------------------------------------------------------------

# mon__registered_projects — cron 登録 ∪ supervisor 管理下 のプロジェクト名 (一意)
mon__registered_projects() {
  {
    cron__list 2>/dev/null | awk -F'|' '$2!="" {print $2}'
    if [[ -d "$SUP_DIR" ]]; then
      local f
      for f in "$SUP_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        # json_get は改行を付けないため明示的に改行する (複数ファイルの連結防止)
        printf '%s\n' "$(json_get "$f" '.project' '')"
      done
    fi
  } | awk 'NF' | sort -u
}

# mon__collect_registered — 「project|session_running|sup_status|restarts|minutes」
mon__collect_registered() {
  local p safe running sup_status restarts minutes
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    safe="$(ccsu_safe_name "$p")"
    if "$TMUX_BIN" has-session -t "claudeos-$safe" 2>/dev/null; then running=1; else running=0; fi
    sup_status="$(sup__get "$p" status '-')"
    restarts="$(sup__get "$p" restarts_today '-')"
    minutes="$(sup__get "$p" minutes_today '-')"
    printf '%s|%s|%s|%s|%s\n' "$p" "$running" "$sup_status" "$restarts" "$minutes"
  done < <(mon__registered_projects)
}

# mon__remove_cron_for <project> — 当該プロジェクトの CLAUDEOS cron を全削除。削除数を stdout
mon__remove_cron_for() {
  local project="$1" id p count=0 r
  while IFS='|' read -r id p _; do
    [[ "$p" == "$project" ]] || continue
    r="$(cron__remove "$id")"; count=$(( count + r ))
  done < <(cron__list 2>/dev/null)
  printf '%s' "$count"
}

# mon__supervise_start <project> — cron 競合があれば外して supervisor 開始
mon__supervise_start() {
  local project="$1" force="" ans n
  if cron__list 2>/dev/null | awk -F'|' -v p="$project" '$2==p{f=1} END{exit !f}'; then
    read -rp "  cron 登録を外して supervisor に切替えますか? [Y/n]: " ans || true
    if [[ "${ans,,}" != "n" && "${ans,,}" != "no" ]]; then
      n="$(mon__remove_cron_for "$project")"; log_ok "cron 削除: $project ($n 件)"
    else
      force="--force"
    fi
  fi
  bash "$SCRIPT_DIR/autonomy.sh" start "$project" ${force:+$force} || true
}

# mon__action <l|s|x> — 登録一覧から選んでアクション実行 (ダッシュボードのサブ操作)
mon__action() {
  local key="$1" label
  local -a regs; mapfile -t regs < <(mon__registered_projects)
  tput cnorm 2>/dev/null || true
  clear 2>/dev/null || true
  case "$key" in
    l) label="起動 (自律1セッション / BG)" ;;
    s) label="supervisor 開始 (Goal到達まで自律再開)" ;;
    x) label="supervisor 停止" ;;
  esac
  printf '\n  %s== %s ==%s\n' "$C_CYAN" "$label" "$C_RESET"
  if (( ${#regs[@]} == 0 )); then
    printf '  登録プロジェクトがありません (項14で cron 登録 / autonomy.sh start)\n'
    read -rp "  Enter で戻る " _ || true; tput civis 2>/dev/null || true; return 0
  fi
  local i; for i in "${!regs[@]}"; do printf '   [%d] %s\n' "$((i + 1))" "${regs[$i]}"; done
  local sel p; read -rp "  番号 (0=キャンセル): " sel || true
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#regs[@]} )); then
    p="${regs[$((sel - 1))]}"
    case "$key" in
      l)
        bash "$SCRIPT_DIR/cron-schedule.sh" run-now --project "$p" || true
        # Wait up to 30s for the tmux session to actually appear (cron-launcher.sh
        # has ~1-3s of Python3 initialization before tmux new-session runs)
        local _safe _session _i _found=0
        _safe="$(ccsu_safe_name "$p")"
        _session="claudeos-$_safe"
        printf '  起動確認中'
        for ((_i = 0; _i < 60; _i++)); do
          if "$TMUX_BIN" has-session -t "$_session" 2>/dev/null; then
            _found=1; break
          fi
          sleep 0.5
          printf '.'
        done
        if (( _found )); then
          printf '\n  %s✓ セッション起動: %s%s\n' "$C_GREEN" "$_session" "$C_RESET"
        else
          printf '\n  %s⚠ 起動待ちタイムアウト (BG 継続中): %s%s\n' "$C_YELLOW" "$_session" "$C_RESET"
        fi
        ;;
      s) mon__supervise_start "$p" ;;
      x) bash "$SCRIPT_DIR/autonomy.sh" stop "$p" || true ;;
    esac
    read -rp "  Enter で戻る " _ || true
  fi
  tput civis 2>/dev/null || true
}

# mon__deregister — 登録プロジェクトを一覧から選んで削除
#   削除対象: cron エントリ / supervisor state file / stop file
#   tmux セッション停止は任意確認
mon__deregister() {
  local -a regs; mapfile -t regs < <(mon__registered_projects)
  tput cnorm 2>/dev/null || true
  clear 2>/dev/null || true
  printf '\n  %s== 🗑️  登録削除 ==%s\n' "$C_RED" "$C_RESET"
  if (( ${#regs[@]} == 0 )); then
    printf '  登録プロジェクトがありません\n'
    read -rp "  Enter で戻る " _ || true; tput civis 2>/dev/null || true; return 0
  fi
  local i p safe cron_n sup_file
  for i in "${!regs[@]}"; do
    p="${regs[$i]}"
    safe="$(ccsu_safe_name "$p")"
    # 現在の状態バッジを表示
    printf '   %s[%d]%s %-28s %s' "$C_YELLOW" "$((i + 1))" "$C_RESET" "$p" "$(mon__project_state_badge "$p")"
    printf '\n'
  done
  local sel; read -rp "  削除する番号 (0=キャンセル): " sel || true
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#regs[@]} )); then
    printf '  キャンセルしました\n'
    read -rp "  Enter で戻る " _ || true; tput civis 2>/dev/null || true; return 0
  fi
  p="${regs[$((sel - 1))]}"
  safe="$(ccsu_safe_name "$p")"
  sup_file="$(sup__state_file "$p")"

  # 削除内容をプレビュー
  printf '\n  %s削除対象: %s%s\n' "$C_RED" "$p" "$C_RESET"
  cron_n="$(cron__list 2>/dev/null | awk -F'|' -v pp="$p" '$2==pp{c++} END{print c+0}')"
  printf '   - cron エントリ: %s 件\n' "$cron_n"
  if [[ -f "$sup_file" ]]; then
    printf '   - supervisor state: %s\n' "$sup_file"
  fi
  if [[ -f "$(sup__stop_file "$p")" ]]; then
    printf '   - supervisor stop flag: %s\n' "$(sup__stop_file "$p")"
  fi
  if "$TMUX_BIN" has-session -t "claudeos-$safe" 2>/dev/null; then
    printf '   - tmux セッション: claudeos-%s (稼働中)\n' "$safe"
  fi

  printf '\n'
  local ans; read -rp "  本当に削除しますか? (Y/N): " ans || true
  if [[ "${ans^^}" != "Y" ]]; then
    printf '  キャンセルしました\n'
    read -rp "  Enter で戻る " _ || true; tput civis 2>/dev/null || true; return 0
  fi

  # supervisor 停止 (実行中なら): --now で pid + tmux + keeper を同期 kill してから
  # 下で state/stop flag を削除する。協調 stop (flag 書き込みのみで即 return) だと
  # supervisor が flag を処理する前に flag を消してしまい、停止要求を見失った
  # zombie supervisor が state を再生成する (= 登録削除が無効化される) レースになる。
  if sup__is_running "$p" 2>/dev/null || [[ -f "$sup_file" ]]; then
    bash "$SCRIPT_DIR/autonomy.sh" stop "$p" --now 2>/dev/null || true
  fi

  # cron 削除
  if (( cron_n > 0 )); then
    local removed; removed="$(mon__remove_cron_for "$p")"
    log_ok "cron 削除: $p ($removed 件)"
  fi

  # supervisor state file / stop file 削除
  [[ -f "$sup_file" ]] && rm -f "$sup_file" && log_ok "supervisor state 削除: $sup_file"
  local _stop_f; _stop_f="$(sup__stop_file "$p")"
  [[ -f "$_stop_f" ]] && rm -f "$_stop_f"

  # tmux セッションが残っていれば停止 (登録削除 = 完全 teardown)。
  # stop --now で supervisor 管理セッションは既に kill 済みのため、ここに残るのは
  # supervisor を伴わない手動起動セッションのみ。登録を消しつつセッションだけ生かす
  # 選択肢は矛盾するため、Y/N 確認なしで無条件 teardown する。
  if "$TMUX_BIN" has-session -t "claudeos-$safe" 2>/dev/null; then
    "$TMUX_BIN" kill-session -t "claudeos-$safe" 2>/dev/null && log_ok "tmux セッション停止: claudeos-$safe" || true
  fi

  log_ok "登録削除完了: $p"
  read -rp "  Enter で戻る " _ || true
  tput civis 2>/dev/null || true
}

# ------------------------------------------------------------
# 新規プロジェクトのオンボード (n キー: 全プロジェクトから選んで管理下へ)
# ------------------------------------------------------------

# mon__all_projects — プロジェクト列挙 (config_project_list: dir かつ Git リポジトリのみ)
mon__all_projects() { config_project_list; }

# mon__project_state_badge <project> — 現状を表す状態バッジ (誤操作防止の可視化)
mon__project_state_badge() {
  local project="$1" safe; safe="$(ccsu_safe_name "$project")"
  if sup__is_running "$project"; then printf '🔁 自律中(supervisor)'; return 0; fi
  if "$TMUX_BIN" has-session -t "claudeos-$safe" 2>/dev/null; then printf '🟢 稼働中'; return 0; fi
  if cron__list 2>/dev/null | awk -F'|' -v p="$project" '$2==p {f=1} END{exit !f}'; then printf '📅 cron登録'; return 0; fi
  printf '⚪ 未管理'
}

# mon__cron_register <project> — cron スケジュール登録 (cron-schedule.sh add へ委譲)
mon__cron_register() {
  local project="$1" t d
  read -rp "  時刻 (HH:MM): " t || true
  printf '  0=日 1=月 2=火 3=水 4=木 5=金 6=土 (月〜土なら 1,2,3,4,5,6)\n'
  read -rp "  曜日 (例 1,2,3,4,5,6): " d || true
  if [[ -n "$t" && -n "$d" ]]; then
    bash "$SCRIPT_DIR/cron-schedule.sh" add --project "$project" --time "$t" --dow "$d" || log_warn "cron 登録に失敗"
  else
    log_warn "時刻/曜日が未入力のためキャンセル"
  fi
}

# mon__is_github <project> — .git + remote origin があれば 0 (GitHub レポジトリ判定)
mon__is_github() {
  local d; d="$(config_projects_dir)/$1"
  [[ -d "$d/.git" ]] || return 1
  git -C "$d" remote get-url origin >/dev/null 2>&1
}

# mon__onboard [filter] — 全プロジェクトを 状態/GitHub バッジ付きで選び、自律管理に追加
#   filter="unmanaged" で未管理(⚪)のみ表示 (u/a キーで切替)
mon__onboard() {
  local filter="${1:-}"
  local -a all; mapfile -t all < <(mon__all_projects)
  local -a projs=(); local p
  for p in "${all[@]}"; do
    if [[ "$filter" == "unmanaged" && "$(mon__project_state_badge "$p")" != *"未管理"* ]]; then continue; fi
    projs+=("$p")
  done
  tput cnorm 2>/dev/null || true
  clear 2>/dev/null || true
  printf '\n  %s== 🆕 新規プロジェクトを自律管理に追加%s ==%s\n' \
    "$C_CYAN" "$([[ "$filter" == unmanaged ]] && printf ' (未管理のみ)')" "$C_RESET"
  if (( ${#projs[@]} == 0 )); then
    printf '  対象プロジェクトがありません%s\n' "$([[ "$filter" == unmanaged ]] && printf ' (未管理なし)')"
    read -rp "  Enter で戻る " _ || true; tput civis 2>/dev/null || true; return 0
  fi
  local i gh; for i in "${!projs[@]}"; do
    if mon__is_github "${projs[$i]}"; then gh="🐙"; else gh="　"; fi
    printf '   %s[%d]%s %s %-30s %s\n' "$C_YELLOW" "$((i + 1))" "$C_RESET" "$gh" "${projs[$i]}" "$(mon__project_state_badge "${projs[$i]}")"
  done
  printf '   %s🐙=GitHubレポジトリ  ⚪未管理 が追加候補  番号を選ぶと管理方法を選べます%s\n' "$C_GRAY" "$C_RESET"
  local sel p; read -rp "  追加する番号 (0=キャンセル / u=未管理のみ / a=全表示): " sel || true
  case "$sel" in
    u|U) mon__onboard unmanaged; return 0 ;;
    a|A) mon__onboard; return 0 ;;
  esac
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#projs[@]} )); then
    p="${projs[$((sel - 1))]}"
    clear 2>/dev/null || true   # 32件リストを消してアクションメニューを見やすく
    printf '\n  %s🆕 %s をどう自律管理しますか?%s\n\n' "$C_CYAN" "$p" "$C_RESET"
    printf '   %s[1]%s 🔁 supervisor 開始  (Goal到達まで自動で再開し続ける)\n' "$C_GREEN" "$C_RESET"
    printf '   %s[2]%s ▶️  1回だけ自律起動 (BG)  (まず1セッションだけ試す)\n' "$C_GREEN" "$C_RESET"
    printf '   %s[3]%s 📅 cron スケジュール登録  (毎週この曜日・時刻に動かす)\n' "$C_GREEN" "$C_RESET"
    printf '   %s[0]%s キャンセル\n\n' "$C_GRAY" "$C_RESET"
    local act; read -rp "  番号を選択: " act || true
    case "$act" in
      1) mon__supervise_start "$p" ;;
      2) bash "$SCRIPT_DIR/cron-schedule.sh" run-now --project "$p" || true ;;
      3) mon__cron_register "$p" ;;
      *) printf '  キャンセルしました\n' ;;
    esac
    read -rp "  Enter で監視ダッシュボードへ戻る " _ || true
  fi
  tput civis 2>/dev/null || true
}

# ------------------------------------------------------------
# 描画
# ------------------------------------------------------------
mon__hr() { printf '  %s%s%s\n' "$C_GRAY" "$(printf '─%.0s' {1..56})" "$C_RESET"; }

mon__render_once() {
  local stamp; stamp="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '\n  %s🎛️  ClaudeOS コントロールセンター%s  (%s秒更新)   %s%s%s\n' \
    "$C_CYAN" "$C_RESET" "$MON_REFRESH" "$C_GRAY" "$stamp" "$C_RESET"
  mon__hr
  # --- 実行中セッション (タブ) ---
  printf '   %s● 実行中セッション%s  %s#  %-22s %-9s %-9s%s\n' \
    "$C_GREEN" "$C_RESET" "$C_GRAY" "プロジェクト" "経過" "残り" "$C_RESET"
  local any=0 tab proj el rem has ic rem_s
  while IFS='|' read -r tab proj el rem has; do
    [[ -z "$tab" ]] && continue
    any=1
    ic="$(mon__status_icon "$rem" "$has")"
    if [[ "$has" == "1" ]]; then rem_s="$(mon__fmt_hms "$rem")"; else rem_s="—"; fi
    printf '   %s%2s%s  %-22s %-9s %-9s %s\n' \
      "$C_YELLOW" "$tab" "$C_RESET" "$proj" "$(mon__fmt_hms "$el")" "$rem_s" "$ic"
  done < <(mon__collect)
  (( any == 0 )) && printf '   %s(実行中なし)%s\n' "$C_GRAY" "$C_RESET"
  mon__hr
  # --- 登録プロジェクト + supervisor ---
  # NOTE: CJK header compensation: "プロジェクト"=6chars×2display_cols=12display.
  #       %-20s → 6chars+14spaces = 12+14=26 display cols (matches data %-26s).
  printf '   %s● 登録 / supervisor%s  %s#  %-20s %-4s %-14s %5s%s\n' \
    "$C_GREEN" "$C_RESET" "$C_GRAY" "プロジェクト" "tmux" "supervisor" "rst/min" "$C_RESET"
  local rn=0 rp rrun rstat rrst rmin sicon supcol
  while IFS='|' read -r rp rrun rstat rrst rmin; do
    [[ -z "$rp" ]] && continue
    rn=$(( rn + 1 ))
    # ASCII sicon avoids CJK double-width misalignment
    if [[ "$rrun" == "1" ]]; then sicon="on "; else sicon="off"; fi
    case "$rstat" in
      running)            supcol="$C_GREEN" ;;
      goal-reached)       supcol="$C_CYAN" ;;
      blocked|crash-loop) supcol="$C_RED" ;;
      *)                  supcol="$C_GRAY" ;;
    esac
    printf '   %s%2s%s  %-26s %-4s %s%-14s%s %3s/%-3s\n' \
      "$C_YELLOW" "$rn" "$C_RESET" "$rp" "$sicon" "$supcol" "$rstat" "$C_RESET" "$rrst" "$rmin"
  done < <(mon__collect_registered)
  (( rn == 0 )) && printf '   %s(登録なし — 項14 cron 登録 / autonomy.sh start)%s\n' "$C_GRAY" "$C_RESET"
  mon__hr
  printf '   %s[1-9]%s介入FG %sCtrl-b 0%s監視 %s[n]%s新規追加 %s[l]%s起動 %s[s]%s監督開始 %s[x]%s監督停止 %s[d]%s登録削除 %s[q]%s終了\n' \
    "$C_GREEN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_YELLOW" "$C_RESET" \
    "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$C_RESET" "$C_RED" "$C_RESET" "$C_YELLOW" "$C_RESET"
  printf '   %s※ 操作キーはこの画面でのみ有効。Claude介入中は Ctrl-b 0 で戻ってから押す%s\n' "$C_GRAY" "$C_RESET"
}

# mon__dashboard — window 0 で動くライブループ (open が内部起動)
#   チラつき防止: 毎フレーム clear せず、カーソルをホームへ戻して上書き描画し、
#   末尾の残り行だけ消す (tput ed)。clear の全消去フラッシュを避ける。
mon__dashboard() {
  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true' EXIT
  clear 2>/dev/null || true   # 初回のみ全消去 (以降は上書きでチラつき防止)
  local key
  while true; do
    mon__sync_tabs
    tput cup 0 0 2>/dev/null || printf '\033[H'   # ホームへ移動 (clear しない)
    mon__render_once
    tput ed 2>/dev/null || printf '\033[J'        # カーソル以降の残り行を消去
    key=''
    read -rsn1 -t "$MON_REFRESH" key 2>/dev/null || true
    case "$key" in
      q|Q) break ;;
      [1-9]) "$TMUX_BIN" select-window -t "$MON_SESSION:$key" 2>/dev/null || true ;;
      n|N) mon__onboard ;;
      l|L) mon__action l ;;
      s|S) mon__action s ;;
      x|X) mon__action x ;;
      d|D) mon__deregister ;;
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
  # 常にダッシュボード(window名 monitor)を選択してから接続する。
  # 前回プロジェクトタブ(Claude)を見たまま離脱していても、開いた直後は必ず
  # ダッシュボードに居るので n/l/s/x が効く (キーが Claude に入る誤操作を防ぐ)。
  local dw
  dw="$("$TMUX_BIN" list-windows -t "$MON_SESSION" -F '#{window_index} #{window_name}' 2>/dev/null | awk '$2=="monitor"{print $1; exit}')"
  [[ -n "$dw" ]] && "$TMUX_BIN" select-window -t "$MON_SESSION:$dw" 2>/dev/null || true
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

キー操作 (コントロールセンター表示中):
  [1-9]     その番号のプロジェクトタブへ切替 (フォアグラウンド/介入)
  Ctrl-b 0  ダッシュボードへ戻る   Ctrl-b n/p  次/前のタブ (tmux 標準)
  [n]       全プロジェクトから選んで自律管理に追加 (supervisor / 1回起動 / cron登録)
  [l]       登録から選んで自律1セッション起動 (BG)
  [s]       登録から選んで supervisor 開始 (Goal到達まで自律再開)
  [x]       supervisor 停止
  [d]       登録削除 (cron/supervisor state を削除してプロジェクトを管理外へ)
  [q]       ダッシュボードを終了 (各セッション/supervisor は継続)
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
