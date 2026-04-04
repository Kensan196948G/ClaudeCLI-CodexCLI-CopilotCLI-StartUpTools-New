import base64
import errno
import os
import pty
import select
import signal
import sys
import termios
import time
import tty


def main() -> int:
    startup_cmd = base64.b64decode(os.environ["STARTUP_CMD_B64"]).decode("utf-8")
    prompt_text = base64.b64decode(os.environ["PROMPT_B64"]).decode("utf-8")

    pid, master_fd = pty.fork()
    if pid == 0:
        os.execvp("bash", ["bash", "-lc", startup_cmd])

    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()
    old_tty = termios.tcgetattr(stdin_fd)
    tty.setraw(stdin_fd)
    os.set_blocking(stdin_fd, False)
    os.set_blocking(master_fd, False)

    buffer = b""
    prompt_sent = False
    deadline = time.time() + 8
    activity_deadline = time.time() + 3

    def send_initial_prompt() -> None:
        nonlocal prompt_sent
        if prompt_sent:
            return

        payload = prompt_text
        if not payload.endswith("\n"):
            payload += "\n"

        # Send as bracketed paste so Claude treats the whole startup prompt
        # as one pasted block, then submit with Enter after the paste closes.
        os.write(master_fd, b"\x1b[200~")
        os.write(master_fd, payload.encode("utf-8"))
        os.write(master_fd, b"\x1b[201~")
        time.sleep(0.25)
        os.write(master_fd, b"\r")
        prompt_sent = True

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

                os.write(stdout_fd, data)
                buffer = (buffer + data)[-16384:]
                activity_deadline = time.time() + 1.0
                if (not prompt_sent) and (
                    "❯".encode("utf-8") in buffer
                    or b'Try "' in buffer
                    or b"Resume this session with:" in buffer
                    or b"SessionStart:startup says:" in buffer
                    or time.time() >= deadline
                ):
                    send_initial_prompt()
                continue

            if (not prompt_sent) and (time.time() >= deadline or time.time() >= activity_deadline):
                send_initial_prompt()

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

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
