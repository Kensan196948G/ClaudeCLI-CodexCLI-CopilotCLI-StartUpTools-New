#!/usr/bin/env bash
# ============================================================
# cron-schedule.sh — Cron 登録・編集・削除 TUI (Linux native)
#
# 移植元: scripts/main/New-CronSchedule.ps1 (メニュー項14)
# 変更点: ssh ls → ローカル ls / SSH crontab → cron-manager.sh (ローカル)
#
# 使い方:
#   cron-schedule.sh                  # 対話メニュー
#   cron-schedule.sh list             # 一覧 (非対話)
#   cron-schedule.sh add --project P --time 21:00 --dow 1,2,3,4,5,6 [--duration 300]
#   cron-schedule.sh remove --id <id>
#   cron-schedule.sh remove-all
#   cron-schedule.sh run-now --project P [--duration 300] [--foreground]  # 既定 BG
#   cron-schedule.sh launch [--project P[,P2]] [--duration N] [--all]     # 登録から一括 BG
#   cron-schedule.sh bulk-register [--github-only] [--unmanaged-only] [--apply]  # 曜日分散一括登録
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/../lib/config-loader.sh"
# shellcheck source=lib/cron-manager.sh
source "$SCRIPT_DIR/../lib/cron-manager.sh"

CRON_LAUNCHER="${CCSU_CRON_LAUNCHER:-$HOME/.claudeos/cron-launcher.sh}"
DEFAULT_DURATION=300

# --- プロジェクト一覧 (config_project_list: dir かつ Git リポジトリのみ) ---
cs__project_list() { config_project_list; }

# --- 一覧表示 (cron__format_display で整形) ---
cs__list_display() {
  local id project duration created expr found=0
  while IFS='|' read -r id project duration created expr; do
    [[ -z "$id" ]] && continue
    found=1
    cron__format_display "$id" "$project" "$duration" "$created" "$expr"
    printf '\n'
  done < <(cron__list)
  (( found == 0 )) && log_info "登録された CLAUDEOS cron エントリはありません"
  return 0
}

# --- 非対話: add ---
cs__add() {
  local project="" duration="$DEFAULT_DURATION" time="" dow=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)  project="$2"; shift 2 ;;
      --duration) duration="$2"; shift 2 ;;
      --time)     time="$2"; shift 2 ;;
      --dow)      dow="$2"; shift 2 ;;
      *) log_error "add: 不明な引数: $1"; return 1 ;;
    esac
  done
  [[ -n "$project" && -n "$time" && -n "$dow" ]] || { log_error "add: --project / --time / --dow は必須"; return 1; }
  local -a dows; IFS=',' read -ra dows <<< "$dow"
  local id
  id="$(cron__add "$project" "$duration" "$time" "${dows[@]}")" || return 1
  log_ok "登録: id=$id project=$project time=$time dow=$dow duration=${duration}m"
}

# --- 非対話: remove ---
cs__remove() {
  local id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="$2"; shift 2 ;;
      *) log_error "remove: 不明な引数: $1"; return 1 ;;
    esac
  done
  [[ -n "$id" ]] || { log_error "remove: --id は必須"; return 1; }
  local n; n="$(cron__remove "$id")"
  if [[ "$n" -gt 0 ]]; then log_ok "削除: id=$id ($n 件)"; else log_warn "該当エントリなし: id=$id"; fi
}

# --- BG 起動: cron-launcher.sh を端末から切り離して非ブロッキング起動 ---
#   setsid (無ければ nohup) で起動。claude UI は tmux セッション claudeos-<safe> に入り、
#   ライブ監視タブ (monitor-sessions.sh) / 項15 / tmux attach で後から閲覧できる。
cs__launch_bg() {
  local project="$1" duration="${2:-$DEFAULT_DURATION}" safe logp runner
  [[ -n "$project" ]] || { log_error "BG 起動: project が空です"; return 1; }
  [[ -f "$CRON_LAUNCHER" ]] || { log_error "cron-launcher.sh が見つかりません: $CRON_LAUNCHER"; return 1; }
  safe="$(ccsu_safe_name "$project")"
  mkdir -p "$CRON_LOGS_DIR"
  logp="$CRON_LOGS_DIR/cron-$(date +%Y%m%d-%H%M%S)-${safe}.log"
  if has_cmd setsid; then runner=setsid; else runner=nohup; fi
  "$runner" bash "$CRON_LAUNCHER" "$project" "$duration" >> "$logp" 2>&1 < /dev/null &
  disown 2>/dev/null || true
  log_ok "BG 起動: $project (duration=${duration}m) → claudeos-${safe}"
  log_info "  ログ: $logp"
  log_info "  監視: メニュー MO (ライブ監視タブ) / 項15 / tmux attach -t claudeos-${safe}"
}

# --- 登録済み cron プロジェクト一覧 (重複除外。出力: project<TAB>duration) ---
cs__registered_projects() {
  cron__list | awk -F'|' 'NF>=3 && $2!="" && !seen[$2]++ { print $2"\t"$3 }'
}

# --- 非対話/対話: 登録済みプロジェクトを選んで一括 BG 起動 ---
#   cs__launch [--project P[,P2,...]] [--duration N] [--all]
#   引数なし → 登録一覧から番号 (複数可: 1,3 / すべて: a) を選択
cs__launch() {
  local projects_csv="" duration="" all=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)  projects_csv="$2"; shift 2 ;;
      --duration) duration="$2"; shift 2 ;;
      --all)      all=1; shift ;;
      *) log_error "launch: 不明な引数: $1"; return 1 ;;
    esac
  done

  # 「project<TAB>duration」の登録一覧を読む
  local -a reg_p=() reg_d=(); local p d
  while IFS=$'\t' read -r p d; do
    [[ -z "$p" ]] && continue
    reg_p+=("$p"); reg_d+=("${d:-$DEFAULT_DURATION}")
  done < <(cs__registered_projects)

  local -a chosen_p=() chosen_d=()
  if [[ -n "$projects_csv" ]]; then
    # 明示指定: 登録 duration があれば流用、無ければ既定
    local -a names; IFS=',' read -ra names <<< "$projects_csv"
    local nm i
    for nm in "${names[@]}"; do
      [[ -z "$nm" ]] && continue
      local dd="$DEFAULT_DURATION"
      for i in "${!reg_p[@]}"; do
        if [[ "${reg_p[$i]}" == "$nm" ]]; then dd="${reg_d[$i]}"; break; fi
      done
      chosen_p+=("$nm"); chosen_d+=("${duration:-$dd}")
    done
  elif (( all )); then
    local i
    for i in "${!reg_p[@]}"; do chosen_p+=("${reg_p[$i]}"); chosen_d+=("${duration:-${reg_d[$i]}}"); done
  else
    # 対話選択
    (( ${#reg_p[@]} == 0 )) && { log_warn "登録済み cron プロジェクトがありません ([1] 新規登録で追加してください)"; return 0; }
    local i
    for i in "${!reg_p[@]}"; do printf '  [%d] %s (%sm)\n' "$((i+1))" "${reg_p[$i]}" "${reg_d[$i]}" >&2; done
    printf '  複数可: 1,3 / すべて: a\n' >&2
    local raw; read -rp "  起動する番号: " raw
    raw="$(printf '%s' "$raw" | tr -d ' ')"
    if [[ "${raw,,}" == "a" || "${raw,,}" == "all" ]]; then
      for i in "${!reg_p[@]}"; do chosen_p+=("${reg_p[$i]}"); chosen_d+=("${reg_d[$i]}"); done
    else
      local -a idxs; IFS=',' read -ra idxs <<< "$raw"
      local n
      for n in "${idxs[@]}"; do
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#reg_p[@]} )); then
          chosen_p+=("${reg_p[$((n-1))]}"); chosen_d+=("${reg_d[$((n-1))]}")
        fi
      done
    fi
  fi

  (( ${#chosen_p[@]} == 0 )) && { log_warn "起動対象がありません"; return 0; }
  local i
  for i in "${!chosen_p[@]}"; do
    cs__launch_bg "${chosen_p[$i]}" "${chosen_d[$i]}" || log_warn "起動失敗: ${chosen_p[$i]}"
  done
  log_ok "${#chosen_p[@]} 件を BG 起動しました"
}

# --- 非対話: run-now (BG 既定。--foreground で従来の同期実行) ---
cs__run_now() {
  local project="" duration="$DEFAULT_DURATION" fg=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)         project="$2"; shift 2 ;;
      --duration)        duration="$2"; shift 2 ;;
      --foreground|--fg) fg=1; shift ;;
      --background|--bg) fg=0; shift ;;
      *) log_error "run-now: 不明な引数: $1"; return 1 ;;
    esac
  done
  [[ -n "$project" ]] || { log_error "run-now: --project は必須"; return 1; }
  [[ -f "$CRON_LAUNCHER" ]] || { log_error "cron-launcher.sh が見つかりません: $CRON_LAUNCHER"; return 1; }
  if (( fg )); then
    log_info "今すぐ実行 (フォアグラウンド): $project (duration=${duration}m)"
    bash "$CRON_LAUNCHER" "$project" "$duration"
  else
    cs__launch_bg "$project" "$duration"
  fi
}

# --- GitHub レポジトリ判定 (.git + remote origin) ---
cs__is_github() {
  local d; d="$(config_projects_dir)/$1"
  [[ -d "$d/.git" ]] || return 1
  git -C "$d" remote get-url origin >/dev/null 2>&1
}

# --- cron 登録済み / supervisor 管理下 判定 ---
cs__is_cron_registered() { cron__list 2>/dev/null | awk -F'|' -v p="$1" '$2==p{f=1} END{exit !f}'; }
cs__is_supervised() { [[ -f "${CCSU_SUP_DIR:-$HOME/.claudeos/supervisor}/$(ccsu_safe_name "$1").json" ]]; }

# --- 一括 cron 登録 (曜日・時刻に分散。既定 dry-run、--apply で実登録) ---
#   bulk-register [--github-only] [--unmanaged-only] [--start HH] [--spacing H]
#                 [--duration M] [--dow CSV] [--apply]
#   負荷分散: 各プロジェクトを 曜日 round-robin + 時刻スロットで割り当て、全件同時起動を避ける。
cs__bulk_register() {
  local github_only=0 unmanaged_only=0 start_hour=9 spacing="" duration="$DEFAULT_DURATION" dow="1,2,3,4,5,6" apply=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --github-only)    github_only=1; shift ;;
      --unmanaged-only) unmanaged_only=1; shift ;;
      --start)          start_hour="$2"; shift 2 ;;
      --spacing)        spacing="$2"; shift 2 ;;
      --duration)       duration="$2"; shift 2 ;;
      --dow)            dow="$2"; shift 2 ;;
      --apply)          apply=1; shift ;;
      *) log_error "bulk-register: 不明な引数: $1"; return 1 ;;
    esac
  done
  [[ "$start_hour" =~ ^[0-9]+$ && "$duration" =~ ^[0-9]+$ ]] || { log_error "--start / --duration は数値"; return 1; }
  # 既定 spacing: duration を時間換算 (= 重複しない最小間隔)。例 300m → 5h
  [[ -z "$spacing" ]] && spacing=$(( (duration + 59) / 60 ))
  [[ "$spacing" =~ ^[0-9]+$ ]] || { log_error "--spacing は数値"; return 1; }
  (( spacing < 1 )) && spacing=1

  local -a dows; IFS=',' read -ra dows <<< "$dow"
  local ndow=${#dows[@]}
  (( ndow == 0 )) && { log_error "--dow が空"; return 1; }
  # 重複警告: 間隔 < duration なら同日のセッションが重なる
  if (( spacing * 60 < duration )); then
    printf '  %s⚠️ 間隔 %dh < duration %dm: 同日のセッションが重複します(同時実行が増えます)%s\n' \
      "$C_YELLOW" "$spacing" "$duration" "$C_RESET"
  fi

  # 候補収集
  local -a cands=(); local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    (( github_only ))    && { cs__is_github "$p" || continue; }
    if (( unmanaged_only )); then
      cs__is_cron_registered "$p" && continue
      cs__is_supervised "$p" && continue
    fi
    cands+=("$p")
  done < <(cs__project_list)
  (( ${#cands[@]} == 0 )) && { log_warn "対象プロジェクトがありません (条件: github_only=$github_only unmanaged_only=$unmanaged_only)"; return 0; }

  log_info "一括 cron 登録 計画: ${#cands[@]} 件 / 曜日=$dow / 開始 ${start_hour}時 / 間隔 ${spacing}h / duration ${duration}m"
  (( apply == 0 )) && printf '  %s※ DRY-RUN (実登録は --apply を付与)%s\n' "$C_YELLOW" "$C_RESET"

  local i day_idx slot hour d t ok=0 skip=0
  for i in "${!cands[@]}"; do
    day_idx=$(( i % ndow )); slot=$(( i / ndow ))
    d="${dows[$day_idx]}"; hour=$(( start_hour + slot * spacing ))
    if (( hour > 23 )); then printf '  ⚠️  %-30s スロット超過(%d時) → skip\n' "${cands[$i]}" "$hour"; skip=$((skip+1)); continue; fi
    t="$(printf '%02d:00' "$hour")"
    printf '  %-30s %s曜 %s  %sm\n' "${cands[$i]}" "$(cron__dow_label "$d")" "$t" "$duration"
    if (( apply )); then
      if cs__is_cron_registered "${cands[$i]}"; then printf '     (登録済み → skip)\n'; skip=$((skip+1)); continue; fi
      if cron__add "${cands[$i]}" "$duration" "$t" "$d" >/dev/null; then ok=$((ok+1)); else log_warn "登録失敗: ${cands[$i]}"; fi
    fi
  done
  if (( apply )); then
    log_ok "一括登録: 登録 $ok 件 / skip $skip 件"
  else
    printf '  %s適用: 同じ引数に --apply を付けて再実行%s\n' "$C_CYAN" "$C_RESET"
  fi
}

# --- 対話: 曜日選択 (0=日〜6=土、カンマ区切り) ---
cs__prompt_dow() {
  printf '  0=日 1=月 2=火 3=水 4=木 5=金 6=土 (月〜土なら 1,2,3,4,5,6)\n' >&2
  local raw; read -rp "  曜日 (例 1,3,5): " raw
  printf '%s' "$raw" | tr -d ' '
}

# --- 対話: プロジェクト選択 ---
cs__prompt_project() {
  local -a projs; mapfile -t projs < <(cs__project_list)
  if (( ${#projs[@]} == 0 )); then
    local name; read -rp "  プロジェクト名: " name; printf '%s' "$name"; return
  fi
  local i; for i in "${!projs[@]}"; do printf '  [%d] %s\n' "$((i+1))" "${projs[$i]}" >&2; done
  local idx; read -rp "  番号: " idx
  if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#projs[@]} )); then
    printf '%s' "${projs[$((idx-1))]}"
  fi
  return 0   # 範囲外でも空 + exit 0 (set -e 安全)
}

# --- 対話メニュー ---
cs__menu() {
  while true; do
    clear
    printf '\n  %s=== Cron 登録・編集・削除 (ローカル crontab) ===%s\n\n' "$C_CYAN" "$C_RESET"
    printf '    %s[1]%s 新規登録\n' "$C_YELLOW" "$C_RESET"
    printf '    %s[2]%s 一覧\n' "$C_YELLOW" "$C_RESET"
    printf '    %s[4]%s 削除 (ID 指定)\n' "$C_YELLOW" "$C_RESET"
    printf '    %s[5]%s 全解除\n' "$C_YELLOW" "$C_RESET"
    printf '    %s[6]%s 今すぐ実行 (BG既定 / fg は確認あり)\n' "$C_GREEN" "$C_RESET"
    printf '    %s[7]%s 登録から選んで一括BG起動 + ライブ監視\n' "$C_GREEN" "$C_RESET"
    printf '    %s[0]%s 戻る\n\n' "$C_GRAY" "$C_RESET"
    local choice; read -rp "  番号: " choice
    case "$choice" in
      1) local p t d; p="$(cs__prompt_project)"; [[ -z "$p" ]] && { log_warn "プロジェクト未選択"; sleep 1; continue; }
         read -rp "  時刻 (HH:MM): " t; d="$(cs__prompt_dow)"
         cs__add --project "$p" --time "$t" --dow "$d" || log_warn "登録失敗"
         read -rp "  Enter で戻る " _ ;;
      2) cs__list_display; read -rp "  Enter で戻る " _ ;;
      4) cs__list_display; local rid; read -rp "  削除する ID: " rid
         [[ -n "$rid" ]] && { cs__remove --id "$rid" || true; }; read -rp "  Enter で戻る " _ ;;
      5) local n; n="$(cron__remove_all)"; log_ok "全解除: $n 件"; read -rp "  Enter で戻る " _ ;;
      6) local p; p="$(cs__prompt_project)"
         if [[ -n "$p" ]]; then
           local fg; read -rp "  フォアグラウンドで実行しますか? (BG既定) [y/N]: " fg
           if [[ "${fg,,}" == "y" || "${fg,,}" == "yes" ]]; then
             cs__run_now --project "$p" --foreground || true
           else
             cs__run_now --project "$p" || true
           fi
         fi
         read -rp "  Enter で戻る " _ ;;
      7) cs__launch || true
         local op; read -rp "  ライブ監視タブを開きますか? [Y/n]: " op
         [[ "${op,,}" != "n" && "${op,,}" != "no" ]] && bash "$SCRIPT_DIR/monitor-sessions.sh" open || true
         read -rp "  Enter で戻る " _ ;;
      0) return 0 ;;
      *) log_warn "無効な入力"; sleep 1 ;;
    esac
  done
}

main() {
  case "${1:-menu}" in
    list)       cs__list_display ;;
    add)        shift; cs__add "$@" ;;
    remove)     shift; cs__remove "$@" ;;
    remove-all) cron__remove_all; printf '\n' ;;
    run-now)    shift; cs__run_now "$@" ;;
    launch)     shift; cs__launch "$@" ;;
    bulk-register) shift; cs__bulk_register "$@" ;;
    menu|"")    cs__menu ;;
    *) log_error "不明なサブコマンド: $1 (list|add|remove|remove-all|run-now|launch|bulk-register|menu)"; exit 1 ;;
  esac
}

# 直接実行時のみ main を呼ぶ (source 時=テストでは呼ばない)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
