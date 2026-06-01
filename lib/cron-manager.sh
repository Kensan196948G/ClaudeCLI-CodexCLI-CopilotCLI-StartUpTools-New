#!/usr/bin/env bash
# ============================================================
# cron-manager.sh — ローカル crontab 管理 (Linux native)
#
# 移植元: scripts/lib/CronManager.psm1
# 設計:
#   - CLAUDEOS:<id> コメント行で自分のエントリを識別 (他人の cron を壊さない)
#   - SSH round-trip (Invoke-RemoteCrontab) を廃止し、ローカル crontab -l / crontab - に直結
#   - Windows 側ローカルレジストリキャッシュ (cron-registry.json) は廃止
#     → Linux では crontab -l が真実 (SoT)。WebUI 連携は cron__list を使う (Phase 4)
#
# 環境変数で上書き可 (テスト/別環境):
#   CCSU_CRON_PREFIX   : エントリ識別子      (既定 CLAUDEOS)
#   CCSU_CRON_LAUNCHER : cron-launcher.sh パス (既定 ~/.claudeos/cron-launcher.sh)
#   CCSU_CRON_LOGS_DIR : ログ出力先          (既定 ~/.claudeos/logs)
#   CCSU_CRONTAB_BIN   : crontab コマンド    (既定 crontab。bats でスタブ差し替え)
# ============================================================

[[ -n "${_CCSU_CRON_LOADED:-}" ]] && return 0
_CCSU_CRON_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CRON_ENTRY_PREFIX="${CCSU_CRON_PREFIX:-CLAUDEOS}"
CRON_LAUNCHER_PATH="${CCSU_CRON_LAUNCHER:-$HOME/.claudeos/cron-launcher.sh}"
CRON_LOGS_DIR="${CCSU_CRON_LOGS_DIR:-$HOME/.claudeos/logs}"
CRONTAB_BIN="${CCSU_CRONTAB_BIN:-crontab}"

# ------------------------------------------------------------
# cron__read — crontab -l (空でもエラーにしない)
#   PowerShell: Invoke-RemoteCrontab -Action read
# ------------------------------------------------------------
cron__read() { "$CRONTAB_BIN" -l 2>/dev/null || true; }

# ------------------------------------------------------------
# cron__write <content> — crontab - に流し込む
#   PowerShell: Invoke-RemoteCrontab -Action write (System.Diagnostics.Process → 1行)
# ------------------------------------------------------------
cron__write() { printf '%s\n' "$1" | "$CRONTAB_BIN" -; }

# ------------------------------------------------------------
# cron__format_expr <time-HH:MM> <dow...> — cron 式を生成
#   PowerShell: Format-CronExpression。曜日 0(日)-6(土)、月〜土なら 1 2 3 4 5 6
#   例: cron__format_expr 21:00 1 2 3 4 5 6  →  "0 21 * * 1,2,3,4,5,6"
# ------------------------------------------------------------
cron__format_expr() {
  local time="$1"; shift
  local -a dows=("$@")
  [[ "$time" =~ ^([0-9]{1,2}):([0-9]{2})$ ]] || { log_error "時刻は HH:MM 形式で指定 (例 21:00)"; return 1; }
  local hour=$((10#${BASH_REMATCH[1]})) minute=$((10#${BASH_REMATCH[2]}))
  (( hour <= 23 ))   || { log_error "時間は 0-23 の範囲"; return 1; }
  (( minute <= 59 )) || { log_error "分は 0-59 の範囲"; return 1; }
  local d
  for d in "${dows[@]}"; do
    [[ "$d" =~ ^[0-9]+$ ]] && (( d >= 0 && d <= 6 )) || { log_error "曜日は 0(日)〜6(土) の範囲"; return 1; }
  done
  local dow_csv
  dow_csv="$(printf '%s\n' "${dows[@]}" | sort -un | paste -sd,)"
  printf '%d %d * * %s' "$minute" "$hour" "$dow_csv"
}

# ------------------------------------------------------------
# cron__new_id — 8 桁の一意 ID (PowerShell: New-CronEntryId / Guid)
# ------------------------------------------------------------
cron__new_id() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    tr -d - < /proc/sys/kernel/random/uuid | cut -c1-8
  else
    printf '%04x%04x' $((RANDOM)) $((RANDOM))
  fi
}

# ------------------------------------------------------------
# cron__dow_label <0-6> — 日本語曜日 (PowerShell: Get-DayOfWeekLabel)
# ------------------------------------------------------------
cron__dow_label() {
  local labels=(日 月 火 水 木 金 土) d="$1"
  if [[ "$d" =~ ^[0-9]+$ ]] && (( d >= 0 && d <= 6 )); then printf '%s' "${labels[$d]}"; else printf '?'; fi
}

# ------------------------------------------------------------
# cron__list — CLAUDEOS エントリを「id|project|duration|created|cronexpr」で列挙
#   PowerShell: Get-ClaudeOSCronEntry
# ------------------------------------------------------------
cron__list() {
  local raw
  raw="$(cron__read)"
  [[ -z "$raw" ]] && return 0
  local -a lines
  mapfile -t lines <<< "$raw"
  local i line id meta project duration created cronline expr
  for ((i = 0; i < ${#lines[@]}; i++)); do
    line="${lines[$i]}"
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*${CRON_ENTRY_PREFIX}:([A-Za-z0-9_-]+)[[:space:]]*(.*)$ ]]; then
      id="${BASH_REMATCH[1]}"; meta="${BASH_REMATCH[2]}"
      project=""; duration="300"; created=""
      [[ "$meta" =~ project=([^[:space:]]+) ]]  && project="${BASH_REMATCH[1]}"
      [[ "$meta" =~ duration=([0-9]+) ]]        && duration="${BASH_REMATCH[1]}"
      [[ "$meta" =~ created=([^[:space:]]+) ]]  && created="${BASH_REMATCH[1]}"
      cronline="${lines[$((i + 1))]:-}"
      expr="$(printf '%s' "$cronline" | awk '{print $1, $2, $3, $4, $5}')"
      printf '%s|%s|%s|%s|%s\n' "$id" "$project" "$duration" "$created" "$expr"
    fi
  done
}

# ------------------------------------------------------------
# cron__add <project> <duration> <time-HH:MM> <dow...> — エントリ追加。id を stdout
#   PowerShell: Add-ClaudeOSCronEntry。crontab の % は \% エスケープ必須
# ------------------------------------------------------------
cron__add() {
  local project="$1" duration="$2" time="$3"; shift 3
  local -a dows=("$@")
  local expr id created logp cmd comment cronline cur new
  expr="$(cron__format_expr "$time" "${dows[@]}")" || return 1
  id="$(cron__new_id)"
  created="$(date +%Y-%m-%dT%H:%M:%S)"
  # crontab の % は改行扱いのため \% でエスケープ ($ もリテラルにして cron 実行時に展開)
  logp="$CRON_LOGS_DIR/cron-\$(date +\\%Y\\%m\\%d-\\%H\\%M\\%S).log"
  cmd="bash $CRON_LAUNCHER_PATH $project $duration >> $logp 2>&1"
  comment="# $CRON_ENTRY_PREFIX:$id project=$project duration=$duration created=$created"
  cronline="$expr $cmd"
  cur="$(cron__read)"   # コマンド置換で末尾改行は自動除去
  if [[ -n "$cur" ]]; then
    new="${cur}"$'\n'"${comment}"$'\n'"${cronline}"
  else
    new="${comment}"$'\n'"${cronline}"
  fi
  cron__write "$new" || { log_error "crontab 更新に失敗"; return 1; }
  printf '%s' "$id"
}

# ------------------------------------------------------------
# cron__remove <id> — id のエントリ (コメント行 + 直後の cron 行) を削除。削除数を stdout
#   PowerShell: Remove-ClaudeOSCronEntry
# ------------------------------------------------------------
cron__remove() {
  local id="$1" raw removed=0
  raw="$(cron__read)"
  [[ -z "$raw" ]] && { printf '0'; return 0; }
  local -a lines out=()
  mapfile -t lines <<< "$raw"
  local i
  for ((i = 0; i < ${#lines[@]}; i++)); do
    if [[ "${lines[$i]}" =~ ^[[:space:]]*#[[:space:]]*${CRON_ENTRY_PREFIX}:${id}([[:space:]]|$) ]]; then
      ((i++)) || true   # 次行 (cron 式) もスキップ
      ((removed++)) || true
      continue
    fi
    out+=("${lines[$i]}")
  done
  local new=""
  (( ${#out[@]} > 0 )) && new="$(printf '%s\n' "${out[@]}")"
  cron__write "$new" || { log_error "crontab 更新に失敗"; return 1; }
  printf '%s' "$removed"
}

# ------------------------------------------------------------
# cron__remove_all — 全 CLAUDEOS エントリ削除。削除数を stdout
#   PowerShell: Remove-AllClaudeOSCronEntry
# ------------------------------------------------------------
cron__remove_all() {
  local ids count=0 id r
  ids="$(cron__list | cut -d'|' -f1)"
  [[ -z "$ids" ]] && { printf '0'; return 0; }
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    r="$(cron__remove "$id")"
    count=$((count + r))
  done <<< "$ids"
  printf '%s' "$count"
}

# ------------------------------------------------------------
# cron__format_display <id> <project> <duration> <created> <expr> — 表示用整形
#   PowerShell: Format-CronEntryForDisplay
#   入力 expr は "min hour * * dow" の 5 フィールド
# ------------------------------------------------------------
cron__format_display() {
  local id="$1" project="$2" duration="$3" created="$4" expr="$5"
  local -a p; read -ra p <<< "$expr"
  local minute="${p[0]:-0}" hour="${p[1]:-0}" dow="${p[4]:-*}"
  local label="" d; local -a dlist
  IFS=',' read -ra dlist <<< "$dow"
  for d in "${dlist[@]}"; do label+="$(cron__dow_label "$d")/"; done
  label="${label%/}"
  printf '[%s] project=%s  %s %s:%02d  duration=%sm  (created %s)' \
    "$id" "$project" "$label" "$hour" "$((10#${minute:-0}))" "$duration" "$created"
}
