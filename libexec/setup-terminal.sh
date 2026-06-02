#!/usr/bin/env bash
# ============================================================
# setup-terminal.sh — tmux / 端末セットアップ (メニュー項7)
# 移植元: scripts/setup/setup-windows-terminal.ps1 を Linux 向けに転用
#   (Windows Terminal プロファイル → tmux/端末の確認と初期設定)
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

TMUX_CONF_MARKER_BEGIN="# >>> ClaudeOS tmux setup"
TMUX_CONF_MARKER_END="# <<< ClaudeOS tmux setup"
LOCALE_PROFILE_MARKER_BEGIN="# >>> ClaudeOS locale setup"
LOCALE_PROFILE_MARKER_END="# <<< ClaudeOS locale setup"

usage() {
  cat <<'EOF'
Usage: setup-terminal.sh [--check] [--apply] [--install] [--locale-ja] [--yes]

Options:
  --check     現在の tmux / 端末状態を確認する (既定)
  --apply     ~/.claudeos の作業ディレクトリと ~/.tmux.conf 管理ブロックを作成・更新する
  --install   tmux が無い場合に OS のパッケージマネージャでインストールを試みる
  --locale-ja ja_JP.UTF-8 を生成し、既定 LANG を ja_JP.UTF-8 に寄せる
  --yes       --install の確認プロンプトを省略する
  --help      このヘルプを表示する
EOF
}

sudo_prefix() {
  if [[ "$(id -u 2>/dev/null || printf '1')" == "0" ]]; then
    printf ''
  else
    printf 'sudo '
  fi
}

confirm_or_skip() {
  local prompt="$1" yes="${2:-0}" ans
  (( yes == 1 )) && return 0
  [[ -t 0 ]] || return 1
  read -rp "  $prompt [y/N]: " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

detect_install_command() {
  local sudo_cmd; sudo_cmd="$(sudo_prefix)"

  if has_cmd apt-get; then
    printf '%s\n' "${sudo_cmd}apt-get update && ${sudo_cmd}apt-get install -y tmux"
  elif has_cmd dnf; then
    printf '%s\n' "${sudo_cmd}dnf install -y tmux"
  elif has_cmd yum; then
    printf '%s\n' "${sudo_cmd}yum install -y tmux"
  elif has_cmd pacman; then
    printf '%s\n' "${sudo_cmd}pacman -Sy --needed tmux"
  elif has_cmd zypper; then
    printf '%s\n' "${sudo_cmd}zypper install -y tmux"
  elif has_cmd apk; then
    printf '%s\n' "${sudo_cmd}apk add tmux"
  elif has_cmd brew; then
    printf '%s\n' 'brew install tmux'
  else
    return 1
  fi
}

run_install_command() {
  local cmd
  if ! cmd="$(detect_install_command)"; then
    log_warn "対応するパッケージマネージャを検出できません。手動で tmux をインストールしてください。"
    return 1
  fi

  log_info "tmux インストールコマンド: $cmd"
  if ! confirm_or_skip "このコマンドを実行しますか?" "${1:-0}"; then
    if [[ "${1:-0}" != "1" && ! -t 0 ]]; then
      log_warn "--install を非対話で使う場合は --yes を付けてください。"
      return 1
    fi
    log_warn "tmux インストールをスキップしました"
    return 0
  fi

  bash -c "$cmd"
}

locale_ja_available() {
  locale -a 2>/dev/null | grep -Eiq '^ja_JP\.(utf8|UTF-8)$'
}

detect_locale_generate_command() {
  local sudo_cmd; sudo_cmd="$(sudo_prefix)"
  if has_cmd locale-gen; then
    printf '%s\n' "${sudo_cmd}locale-gen ja_JP.UTF-8"
  elif has_cmd localedef; then
    printf '%s\n' "${sudo_cmd}localedef -i ja_JP -f UTF-8 ja_JP.UTF-8"
  else
    return 1
  fi
}

detect_locale_default_command() {
  local sudo_cmd; sudo_cmd="$(sudo_prefix)"
  if has_cmd update-locale; then
    printf '%s\n' "${sudo_cmd}update-locale LANG=ja_JP.UTF-8"
  elif has_cmd localectl; then
    printf '%s\n' "${sudo_cmd}localectl set-locale LANG=ja_JP.UTF-8"
  else
    return 1
  fi
}

apply_user_locale_profile() {
  local profile="$HOME/.profile" tmp
  tmp="$(mktemp)"

  if [[ -f "$profile" ]]; then
    sed "/^${LOCALE_PROFILE_MARKER_BEGIN}$/,/^${LOCALE_PROFILE_MARKER_END}$/d" "$profile" > "$tmp"
    [[ -s "$tmp" ]] && printf '\n' >> "$tmp"
  fi

  cat >> "$tmp" <<EOF
$LOCALE_PROFILE_MARKER_BEGIN
export LANG=ja_JP.UTF-8
$LOCALE_PROFILE_MARKER_END
EOF
  install -m 0644 "$tmp" "$profile"
  rm -f "$tmp"
  log_ok "~/.profile に LANG=ja_JP.UTF-8 を設定しました"
}

apply_japanese_locale() {
  local yes="${1:-0}" cmd

  if locale_ja_available; then
    log_ok "locale: ja_JP.UTF-8 生成済み"
  else
    if cmd="$(detect_locale_generate_command)"; then
      log_info "locale 生成コマンド: $cmd"
      if confirm_or_skip "ja_JP.UTF-8 を生成しますか?" "$yes"; then
        bash -c "$cmd"
      else
        log_warn "ja_JP.UTF-8 の生成をスキップしました"
      fi
    else
      log_warn "locale-gen/localedef が見つかりません。ja_JP.UTF-8 の生成は手動対応が必要です。"
    fi
  fi

  if cmd="$(detect_locale_default_command)"; then
    log_info "locale 既定化コマンド: $cmd"
    if confirm_or_skip "既定 LANG を ja_JP.UTF-8 にしますか?" "$yes"; then
      if bash -c "$cmd"; then
        log_ok "システム既定 LANG を ja_JP.UTF-8 に寄せました"
      else
        log_warn "システム既定 LANG の変更に失敗しました。ユーザー設定へフォールバックします。"
        apply_user_locale_profile
      fi
    else
      log_warn "システム既定 LANG の変更をスキップしました"
    fi
  else
    log_warn "update-locale/localectl が見つかりません。ユーザー設定へフォールバックします。"
    apply_user_locale_profile
  fi

  printf '  反映には再ログイン、または新しい tmux セッションの作り直しが必要です。\n'
}

print_tmux_block() {
  cat <<EOF
$TMUX_CONF_MARKER_BEGIN
set -g mouse on
set -g history-limit 50000
set -g escape-time 10
set -g renumber-windows on
set -g status on
set -g status-interval 5
set -g default-terminal "screen-256color"
set -as terminal-overrides ",xterm-256color:Tc"
bind r source-file ~/.tmux.conf \; display-message "tmux.conf reloaded"
$TMUX_CONF_MARKER_END
EOF
}

apply_tmux_conf() {
  local conf="$HOME/.tmux.conf" tmp
  tmp="$(mktemp)"

  if [[ -f "$conf" ]]; then
    sed "/^${TMUX_CONF_MARKER_BEGIN}$/,/^${TMUX_CONF_MARKER_END}$/d" "$conf" > "$tmp"
    [[ -s "$tmp" ]] && printf '\n' >> "$tmp"
  fi

  print_tmux_block >> "$tmp"
  install -m 0644 "$tmp" "$conf"
  rm -f "$tmp"
  log_ok "~/.tmux.conf を更新しました"
}

apply_directories() {
  mkdir -p "$CCSU_HOME/logs" "$CCSU_HOME/sessions" "$CCSU_HOME/tmp"
  chmod 700 "$CCSU_HOME" 2>/dev/null || true
  log_ok "ClaudeOS 作業ディレクトリを確認しました: $CCSU_HOME"
}

print_status() {
  printf '\n'
  if has_cmd tmux; then
    log_ok "tmux: $(tmux -V 2>/dev/null || echo '検出')"
  else
    local cmd
    log_warn "tmux 未検出"
    if cmd="$(detect_install_command)"; then
      printf '  インストール例: %s\n' "$cmd"
    else
      printf '  OS のパッケージマネージャで tmux をインストールしてください。\n'
    fi
  fi

  local conf="$HOME/.tmux.conf"
  if [[ -f "$conf" ]]; then
    if grep -q "^${TMUX_CONF_MARKER_BEGIN}$" "$conf"; then
      log_ok "~/.tmux.conf ClaudeOS 管理ブロックあり"
    else
      log_ok "~/.tmux.conf あり (ClaudeOS 管理ブロックなし)"
    fi
  else
    log_info "~/.tmux.conf なし"
  fi

  if [[ -d "$CCSU_HOME" ]]; then
    log_ok "ClaudeOS home: $CCSU_HOME"
  else
    log_info "ClaudeOS home 未作成: $CCSU_HOME"
  fi

  printf '  端末: TERM=%s%s%s LANG=%s\n' "$C_GRAY" "${TERM:-未設定}" "$C_RESET" "${LANG:-未設定}"
  case "${LANG:-}" in
    ja_JP.*|C.UTF-8|*.UTF-8|*.utf8) : ;;
    *) printf '  %s日本語表示にするには:%s export LANG=ja_JP.UTF-8\n' "$C_YELLOW" "$C_RESET"
       printf '       (未生成なら: sudo locale-gen ja_JP.UTF-8 && sudo update-locale)\n' ;;
  esac
}

print_next_steps() {
  printf '\n  %sClaudeOS セッションへの接続:%s\n' "$C_CYAN" "$C_RESET"
  printf '    実行中一覧 : tmux ls | grep claudeos-\n'
  printf '    接続       : tmux attach -t claudeos-<project>\n'
  printf '    デタッチ   : Ctrl-b d (セッションは継続)\n'
  printf '    再読込     : tmux source-file ~/.tmux.conf\n'
  printf '\n  %sライブ監視タブ (経過/残り・タブ切替):%s\n' "$C_CYAN" "$C_RESET"
  printf '    開く       : メニュー MO  または  bash bin/monitor-sessions.sh open\n'
  printf '    タブ切替   : Ctrl-b <n> で各プロジェクトを FG / Ctrl-b 0 で監視へ戻る\n'
  printf '    監視終了   : ダッシュボードで q (各プロジェクトは BG で継続)\n'
  printf '\n'
}

main() {
  local apply=0 install_tmux=0 locale_ja=0 yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ;;
      --apply) apply=1 ;;
      --install) install_tmux=1 ;;
      --locale-ja) locale_ja=1 ;;
      --yes) yes=1 ;;
      --help|-h) usage; return 0 ;;
      *) log_error "不明な引数: $1"; usage; return 1 ;;
    esac
    shift
  done

  log_info "tmux / 端末セットアップ"
  print_status

  if (( install_tmux == 1 )) && ! has_cmd tmux; then
    run_install_command "$yes"
  fi

  if (( apply == 0 && install_tmux == 0 && locale_ja == 0 )) && [[ -t 0 ]]; then
    local ans
    read -rp "  tmux / 端末設定を適用しますか? [y/N]: " ans || true
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] && apply=1
  fi

  if (( locale_ja == 0 )) && [[ "${LANG:-}" != ja_JP.* ]] && [[ -t 0 ]]; then
    local ans
    read -rp "  LANG を ja_JP.UTF-8 に寄せますか? [y/N]: " ans || true
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] && locale_ja=1
  fi

  if (( apply == 1 )); then
    apply_directories
    apply_tmux_conf
    print_status
  fi

  if (( locale_ja == 1 )); then
    apply_japanese_locale "$yes"
    print_status
  fi

  print_next_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
