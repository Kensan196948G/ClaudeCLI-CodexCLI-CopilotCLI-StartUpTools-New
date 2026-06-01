#!/usr/bin/env bash
# ============================================================
# common-setup.bash — bats 共通ヘルパ
#
# Pester の BeforeEach/$TestDrive/Mock に相当する仕組みを提供。
# 各 .bats の setup()/teardown() から呼び出す。
# ============================================================

# _bats_common_setup — 各テスト前に実行
#   REPO_ROOT: リポジトリルート (tests/bats/unit などから解決)
#   TEST_TEMP: $TestDrive 相当の一時ディレクトリ
#   STUB_BIN : Mock 相当の PATH スタブ置き場 (PATH 先頭に注入)
_bats_common_setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export REPO_ROOT

  TEST_TEMP="$(mktemp -d)"
  export TEST_TEMP

  STUB_BIN="$TEST_TEMP/stub-bin"
  mkdir -p "$STUB_BIN"
  export STUB_BIN
  PATH="$STUB_BIN:$PATH"
  export PATH
}

# _bats_common_teardown — 各テスト後に実行
_bats_common_teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "$TEST_TEMP" ]] && rm -rf "$TEST_TEMP"
  return 0
}

# make_stub_bin <name> <body...> — PATH 上に偽コマンドを配置 (Mock 相当)
#   例: make_stub_bin crontab 'echo "0 21 * * 1 mycmd"'
#   例: make_stub_bin claude 'echo "claude $*"; exit 0'
make_stub_bin() {
  local name="$1"; shift
  printf '#!/usr/bin/env bash\n%s\n' "$*" > "$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
}
