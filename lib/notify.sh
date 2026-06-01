#!/usr/bin/env bash
# ============================================================
# notify.sh — 通知音再生 (Linux native)
#
# 移植元: scripts/lib/SessionLogger.ps1 の Invoke-LauncherNotificationSound
#         (winmm.dll mciSendString → ffplay/paplay/aplay 多段フォールバック)
#
# 設計: 音声は副次機能。プレイヤ皆無でも return 0 (全体は成功扱い)。
#       CLAUDEOS_SOUND_ENABLED=0 で完全無効化。既定は非ブロッキング再生。
# ============================================================

[[ -n "${_CCSU_NOTIFY_LOADED:-}" ]] && return 0
_CCSU_NOTIFY_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config-loader.sh"

# notify__play <tool> [--wait]
#   tool: claude|codex|copilot (config.notifications.sounds.<tool> を再生)
#   --wait: 再生完了を待つ (既定は非ブロッキング background)
notify__play() {
  local tool="${1:-claude}" wait=0
  [[ "${2:-}" == "--wait" ]] && wait=1

  # 明示無効化
  [[ "${CLAUDEOS_SOUND_ENABLED:-1}" == "0" ]] && return 0
  # config の soundEnabled
  config_sound_enabled || return 0

  local f; f="$(config_sound_path "$tool")" || true
  [[ -n "$f" && -f "$f" ]] || return 0

  # 利用可能な最初のプレイヤを検出
  local player="" p
  for p in ffplay paplay aplay mpg123 cvlc; do
    if has_cmd "$p"; then player="$p"; break; fi
  done
  [[ -z "$player" ]] && { log_warn "音声プレイヤ未検出 (ffplay/paplay/aplay) — 音声スキップ"; return 0; }

  local -a cmd
  case "$player" in
    ffplay) cmd=(ffplay -nodisp -autoexit -loglevel quiet "$f") ;;
    cvlc)   cmd=(cvlc --intf dummy --play-and-exit "$f") ;;
    mpg123) cmd=(mpg123 -q "$f") ;;
    *)      cmd=("$player" "$f") ;;   # paplay/aplay は WAV 想定
  esac

  if (( wait )); then
    "${cmd[@]}" >/dev/null 2>&1 || true
  else
    "${cmd[@]}" >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  return 0
}

# notify__bell — 端末ベル (最終フォールバック)
notify__bell() { printf '\a'; }
