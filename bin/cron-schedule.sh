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
#   cron-schedule.sh run-now --project P [--duration 300]
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

# --- プロジェクト一覧 (ローカル ls。New-CronSchedule の ssh ls を置換) ---
cs__project_list() {
  local base; base="$(config_projects_dir)"
  [[ -d "$base" ]] || return 0
  ls -1 "$base" 2>/dev/null | grep -v '^\.' || true
}

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

# --- 非対話: run-now (cron-launcher.sh を即実行) ---
cs__run_now() {
  local project="" duration="$DEFAULT_DURATION"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)  project="$2"; shift 2 ;;
      --duration) duration="$2"; shift 2 ;;
      *) log_error "run-now: 不明な引数: $1"; return 1 ;;
    esac
  done
  [[ -n "$project" ]] || { log_error "run-now: --project は必須"; return 1; }
  [[ -f "$CRON_LAUNCHER" ]] || { log_error "cron-launcher.sh が見つかりません: $CRON_LAUNCHER"; return 1; }
  log_info "今すぐ実行: $project (duration=${duration}m)"
  bash "$CRON_LAUNCHER" "$project" "$duration"
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
    printf '    %s[6]%s 今すぐ実行\n' "$C_GREEN" "$C_RESET"
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
      6) local p; p="$(cs__prompt_project)"; [[ -n "$p" ]] && { cs__run_now --project "$p" || true; }
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
    menu|"")    cs__menu ;;
    *) log_error "不明なサブコマンド: $1 (list|add|remove|remove-all|run-now|menu)"; exit 1 ;;
  esac
}

# 直接実行時のみ main を呼ぶ (source 時=テストでは呼ばない)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
