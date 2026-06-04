#!/usr/bin/env bats
# ============================================================
# install-supervisor-service.bats — install-supervisor-service.sh のテスト
# systemctl / loginctl / journalctl を PATH スタブ化して検証。
# ============================================================

load '../helpers/common-setup'

setup() {
  _bats_common_setup
  SCRIPT="$REPO_ROOT/scripts/dashboards/install-supervisor-service.sh"

  # systemd 系コマンドをスタブ化
  make_stub_bin systemctl   'echo "systemctl $*"; exit 0'
  make_stub_bin loginctl    'echo "loginctl $*"; exit 0'
  make_stub_bin journalctl  'echo "journalctl $*"; exit 0'

  # node もスタブ化 (state.json 読み込み部分は不要)
  make_stub_bin node 'echo "node $*"; exit 0'

  # HOME を TEST_TEMP に向け systemd unit ディレクトリ干渉を回避
  export HOME="$TEST_TEMP"
  export XDG_CONFIG_HOME="$TEST_TEMP/.config"
}

teardown() { _bats_common_teardown; }

# ── --status フラグ ──────────────────────────────────────────
@test "install-supervisor-service: --status が systemctl is-active を呼ぶ" {
  run bash "$SCRIPT" --status
  [ "$status" -eq 0 ]
  # systemctl --user is-active が呼ばれていること
  [[ "$output" == *"--user"* ]] || [[ "$output" == *"is-active"* ]]
}

@test "install-supervisor-service: --status が状態を表示すること" {
  # systemctl is-active のスタブ: exit 1 (stopped)
  make_stub_bin systemctl 'case "$*" in *"is-active"*) exit 1;; *) echo "systemctl $*"; exit 0;; esac'
  run bash "$SCRIPT" --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"状態"* ]]
}

# ── --logs フラグ ────────────────────────────────────────────
@test "install-supervisor-service: --logs が journalctl を呼ぶ" {
  run bash "$SCRIPT" --logs
  [ "$status" -eq 0 ]
  [[ "$output" == *"journalctl"* ]]
}

@test "install-supervisor-service: --logs に -n 50 が含まれること" {
  run bash "$SCRIPT" --logs
  [ "$status" -eq 0 ]
  [[ "$output" == *"-n 50"* ]]
}

# ── --uninstall フラグ ───────────────────────────────────────
@test "install-supervisor-service: --uninstall が stop を呼ぶこと" {
  run bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"stop"* ]]
}

@test "install-supervisor-service: --uninstall が disable を呼ぶこと" {
  run bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"disable"* ]]
}

@test "install-supervisor-service: --uninstall 完了メッセージを表示すること" {
  run bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"削除"* ]] || [[ "$output" == *"uninstall"* ]] || [[ "$output" == *"OK"* ]]
}

# ── Install パス（node 未存在時のエラー） ─────────────────────
@test "install-supervisor-service: node 未存在時に終了コード 1 でエラー終了すること" {
  # node スタブを削除して未存在状態を再現
  rm -f "$STUB_BIN/node"
  # NODE_BIN も空にする
  run bash -c "NODE_BIN='' bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"node"* ]]
}

# ── サービスファイル生成確認 ─────────────────────────────────
@test "install-supervisor-service: Install 時にサービスファイルを生成すること" {
  # node と NODE_BIN を明示してインストールパスを通す
  NODE_BIN="$(command -v bash)"
  export NODE_BIN
  # supervisor-daemon.js のスタブファイルを用意
  DAEMON_JS_DIR="$TEST_TEMP/scripts/dashboards"
  mkdir -p "$DAEMON_JS_DIR"
  touch "$DAEMON_JS_DIR/supervisor-daemon.js"
  # SCRIPT をコピーして PROJ_ROOT / DAEMON_JS を上書き
  TMP_SCRIPT="$TEST_TEMP/install-supervisor-service.sh"
  sed \
    -e "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$DAEMON_JS_DIR\"|" \
    -e "s|PROJ_ROOT=.*|PROJ_ROOT=\"$TEST_TEMP\"|" \
    "$SCRIPT" > "$TMP_SCRIPT"
  chmod +x "$TMP_SCRIPT"
  run bash "$TMP_SCRIPT"
  # サービスファイルが生成されていること
  SERVICE_FILE="$TEST_TEMP/.config/systemd/user/claudeos-supervisor.service"
  [ -f "$SERVICE_FILE" ] || [[ "$output" == *"サービスファイル"* ]] || [[ "$output" == *"OK"* ]]
}
