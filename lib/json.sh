#!/usr/bin/env bash
# ============================================================
# json.sh — jq ベース JSON 読み書きライブラリ (Linux native)
#
# 役割: PowerShell の ConvertTo-Json / ConvertFrom-Json (157 箇所/19 ファイル)
#       を jq に集約する。config.json / state.json / session.json の
#       読み取り・原子的書き込み・JSONL 追記を統一 API で提供。
#
# 前提: jq が必要。実行エントリ (bin/*.sh) で `require_cmd jq` すること。
#       (このライブラリは source 時に exit しない方針)
#
# 移植元: 各 .psm1 の ConvertFrom-Json / ConvertTo-Json,
#         SessionLogger.ps1 の FileShare::None リトライ → flock
# ============================================================

[[ -n "${_CCSU_JSON_LOADED:-}" ]] && return 0
_CCSU_JSON_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ------------------------------------------------------------
# json_get <file> <jq-filter> [default]
#   スカラ値を取得。file 不在 / null / empty なら default を返す。
#   例: json_get config/config.json '.projects' '/home/kensan/Projects'
#   例: json_get state.json '.maintenance.phase_mode' 'development'
# ------------------------------------------------------------
json_get() {
  local file="$1" filter="$2" default="${3:-}"
  [[ -f "$file" ]] || { printf '%s' "$default"; return 0; }
  local v
  v="$(jq -r "${filter} // empty" "$file" 2>/dev/null || true)"
  if [[ -n "$v" ]]; then printf '%s' "$v"; else printf '%s' "$default"; fi
}

# ------------------------------------------------------------
# json_get_raw <file> <jq-filter>
#   配列/オブジェクトを compact JSON (-c) で取得。下流で再パースする用。
#   例: json_get_raw config/config.json '.tools | keys'
# ------------------------------------------------------------
json_get_raw() {
  local file="$1" filter="$2"
  [[ -f "$file" ]] || return 0
  jq -c "${filter} // empty" "$file" 2>/dev/null || true
}

# ------------------------------------------------------------
# json_valid <file>
#   JSON として妥当なら 0、不正なら 1。
# ------------------------------------------------------------
json_valid() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  jq -e . "$file" >/dev/null 2>&1
}

# ------------------------------------------------------------
# json_set <file> <jq-filter> [jq-args...]
#   jq フィルタを適用して原子的に書き戻す (mktemp + mv)。flock で排他。
#   file 不在時は jq -n で新規生成。
#   例: json_set state.json '.execution.phase = $v' --arg v 'Build'
#   例: json_set state.json '.kpi.blocker_count = ($v|tonumber)' --arg v 0
# ------------------------------------------------------------
json_set() {
  local file="$1"; shift
  local filter="$1"; shift
  local dir tmp lock fd rc=0
  dir="$(dirname "$file")"; mkdir -p "$dir"
  lock="${file}.lock"
  tmp="$(mktemp "${file}.XXXXXX.tmp")" || { log_warn "json_set: mktemp 失敗: $file"; return 1; }

  exec {fd}>"$lock"
  if ! flock -w 5 "$fd"; then
    log_warn "json_set: ロック取得失敗 (skip): $file"
    rm -f "$tmp"; exec {fd}>&-; return 0
  fi

  if [[ -f "$file" ]]; then
    if jq "$@" "$filter" "$file" > "$tmp" 2>/dev/null; then mv -f "$tmp" "$file"; else rc=1; fi
  else
    if jq -n "$@" "$filter" > "$tmp" 2>/dev/null; then mv -f "$tmp" "$file"; else rc=1; fi
  fi

  [[ $rc -ne 0 ]] && { rm -f "$tmp"; log_warn "json_set: jq 適用失敗: $file"; }
  exec {fd}>&-
  return $rc
}

# ------------------------------------------------------------
# json_append_line <file> <line>
#   JSONL ファイルへ 1 行追記 (flock 付き)。launch-metadata-*.jsonl 用。
# ------------------------------------------------------------
json_append_line() {
  local file="$1" line="$2" lock fd
  mkdir -p "$(dirname "$file")"
  lock="${file}.lock"
  exec {fd}>"$lock"
  flock -w 2 "$fd" || { exec {fd}>&-; return 0; }
  printf '%s\n' "$line" >> "$file"
  exec {fd}>&-
}

# ------------------------------------------------------------
# json_expand_path <path>
#   Windows 由来の config 値を Linux パスへ正規化。
#   %USERPROFILE% → $HOME, バックスラッシュ → スラッシュ。
#   例: '%USERPROFILE%\.ai-startup\recent.json' → '$HOME/.ai-startup/recent.json'
# ------------------------------------------------------------
json_expand_path() {
  local p="$1"
  p="${p//%USERPROFILE%/$HOME}"
  p="${p//\\//}"
  printf '%s' "$p"
}
