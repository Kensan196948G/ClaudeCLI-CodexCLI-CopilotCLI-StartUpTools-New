import base64
import errno
import os
import pty
import select
import shlex
import signal
import sys
import termios
import tty


def _write_all(fd: int, data: bytes, max_retries: int = 5) -> None:
    """Write all data to fd, retrying on BlockingIOError with select()."""
    written = 0
    retries = 0
    while written < len(data):
        try:
            n = os.write(fd, data[written:])
            written += n
            retries = 0
        except BlockingIOError:
            retries += 1
            if retries > max_retries:
                lost = len(data) - written
                sys.stderr.write(f"[pty-bridge] stdout buffer full, {lost} bytes lost\n")
                sys.stderr.flush()
                break
            select.select([], [fd], [], 0.2)


def _acquire_instance_lock(project: str) -> "tuple[int | None, str]":
    """
    /tmp/claude_pty_<project>.lock にロックファイルを作成し、
    別インスタンスが stdin を rawモードで取り合うのを防ぐ。
    返り値: (lock_fd, lock_path)  取得失敗時は (None, lock_path)
    """
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in project)
    lock_path = f"/tmp/claude_pty_{safe}.lock"
    try:
        fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY | os.O_EXCL, 0o600)
        os.write(fd, str(os.getpid()).encode())
        return fd, lock_path
    except FileExistsError:
        # 既存ロックファイルのPIDが生きているか確認
        try:
            with open(lock_path, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)  # プロセスが存在すれば例外なし
            return None, lock_path
        except (ValueError, OSError):
            # 古いロック（プロセス死亡）なら強制削除して再取得
            try:
                os.unlink(lock_path)
            except OSError:
                pass
            try:
                fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY | os.O_EXCL, 0o600)
                os.write(fd, str(os.getpid()).encode())
                return fd, lock_path
            except OSError:
                return None, lock_path


def main() -> int:
    startup_cmd_base = base64.b64decode(os.environ["STARTUP_CMD_B64"]).decode("utf-8")
    prompt_text = base64.b64decode(os.environ["PROMPT_B64"]).decode("utf-8")

    # ローカルモードと同様に、プロンプトを CLI 引数として claude に渡す。
    # ブラケットペースト注入はタイミング依存で不安定なため、この方式に統一する。
    startup_cmd = startup_cmd_base + " " + shlex.quote(prompt_text)

    # stdin が実際の TTY でない場合は PTY bridge が正しく動作しない。
    # 同一プロジェクトで多重起動されると stdin を取り合いフリーズするため、
    # プロジェクト名ベースのロックファイルで同時起動を1つに制限する。
    project = os.environ.get("CLAUDE_PROJECT", "default")
    lock_fd, lock_path = _acquire_instance_lock(project)
    if lock_fd is None:
        sys.stderr.write(
            f"[pty-bridge] ERROR: プロジェクト '{project}' の PTY bridge は既に起動中です。\n"
            f"[pty-bridge] 多重起動は stdin (fd 0) の rawモード競合によりフリーズします。\n"
            f"[pty-bridge] ロックファイル: {lock_path}\n"
        )
        sys.stderr.flush()
        return 1

    pid, master_fd = pty.fork()
    if pid == 0:
        os.execvp("bash", ["bash", "-lc", startup_cmd])

    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()
    old_tty = termios.tcgetattr(stdin_fd)
    tty.setraw(stdin_fd)
    os.set_blocking(stdin_fd, False)
    os.set_blocking(master_fd, False)
    os.set_blocking(stdout_fd, False)

    try:
        while True:
            rlist, _, _ = select.select([master_fd, stdin_fd], [], [], 0.2)

            if master_fd in rlist:
                try:
                    data = os.read(master_fd, 4096)
                except BlockingIOError:
                    data = b""
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise

                if not data:
                    break

                _write_all(stdout_fd, data)
                continue

            if stdin_fd in rlist:
                try:
                    user_data = os.read(stdin_fd, 4096)
                except BlockingIOError:
                    user_data = b""

                if user_data:
                    os.write(master_fd, user_data)
    except KeyboardInterrupt:
        try:
            os.kill(pid, signal.SIGINT)
        except OSError:
            pass
    finally:
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_tty)
        # インスタンスロック解放
        try:
            os.close(lock_fd)
            os.unlink(lock_path)
        except OSError:
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
