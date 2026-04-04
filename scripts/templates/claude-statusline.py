#!/usr/bin/env python3
"""Claude Code status line script with ANSI colors.

Reads JSON from stdin, outputs formatted multi-line status bar.
Deployed to each project's .claude/statusline.py by the launcher.
"""
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone, timedelta

JST = timezone(timedelta(hours=9))

# ANSI color codes
CYAN = "\x1b[36m"
GREEN = "\x1b[32m"
YELLOW = "\x1b[33m"
MAGENTA = "\x1b[35m"
BLUE = "\x1b[34m"
WHITE = "\x1b[97m"
GRAY = "\x1b[90m"
RED = "\x1b[31m"
BOLD = "\x1b[1m"
DIM = "\x1b[2m"
R = "\x1b[0m"

SEP = f" {GRAY}\u2502{R} "


def get_git_branch() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=2,
        )
        return result.stdout.strip() if result.returncode == 0 else "?"
    except Exception:
        return "?"


def progress_bar(pct: float, width: int = 10) -> str:
    filled = round(pct / 100 * width)
    empty = width - filled
    if pct >= 80:
        color = RED
    elif pct >= 50:
        color = YELLOW
    else:
        color = GREEN
    return color + "\u25b0" * filled + DIM + "\u25b1" * empty + R


def format_duration(ms: float) -> str:
    total_sec = int(ms / 1000)
    hours = total_sec // 3600
    minutes = (total_sec % 3600) // 60
    if hours > 0:
        return f"{hours}h {minutes:02d}m"
    return f"{minutes}m"


def format_reset_time(epoch: float | int | None) -> str:
    if not epoch:
        return ""
    dt = datetime.fromtimestamp(epoch, tz=JST)
    now = datetime.now(tz=JST)
    if dt.date() == now.date():
        return f"Resets {dt.strftime('%-I%p').lower()} (Asia/Tokyo)"
    return f"Resets {dt.strftime('%b %-d')} at {dt.strftime('%-I%p').lower()} (Asia/Tokyo)"


def main() -> None:
    raw = sys.stdin.read()
    if not raw.strip():
        return

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return

    model = data.get("model", {})
    model_name = model.get("display_name") or model.get("id", "?")

    cwd = data.get("cwd", "")
    project = os.path.basename(cwd) if cwd else "?"

    branch = get_git_branch()
    os_name = platform.system()

    ctx = data.get("context_window", {})
    ctx_pct = ctx.get("used_percentage", 0) or 0

    cost = data.get("cost", {})
    lines_added = cost.get("total_lines_added", 0) or 0
    lines_removed = cost.get("total_lines_removed", 0) or 0
    duration_ms = cost.get("total_duration_ms", 0) or 0

    rate_limits = data.get("rate_limits") or {}
    five_hour = rate_limits.get("five_hour") or {}
    seven_day = rate_limits.get("seven_day") or {}

    # Line 1: Model / Project / Branch / OS
    line1_parts = [
        f"{MAGENTA}\U0001f916 {BOLD}{model_name}{R}",
        f"{YELLOW}\U0001f4c1 {project}{R}",
        f"{GREEN}\U0001f33f {branch}{R}",
        f"{CYAN}\U0001f5a5  {os_name}{R}",
    ]
    print(SEP.join(line1_parts))

    # Line 2: Context % / File changes / Duration
    ctx_bar = progress_bar(ctx_pct)
    line2_parts = [
        f"{BLUE}\U0001f4ca {WHITE}{ctx_pct:.0f}%{R} {ctx_bar}",
        f"{CYAN}\u270f\ufe0f  {GREEN}+{lines_added}{R}/{RED}-{lines_removed}{R}",
    ]
    if duration_ms > 0:
        line2_parts.append(f"{BLUE}\u23f1  {WHITE}{format_duration(duration_ms)}{R}")
    print(SEP.join(line2_parts))

    # Line 3: 5-hour rate limit (if available)
    five_pct = five_hour.get("used_percentage")
    if five_pct is not None:
        five_bar = progress_bar(five_pct)
        five_reset = format_reset_time(five_hour.get("resets_at"))
        print(f"{BLUE}\u23f1  5h{R}  {five_bar}  {WHITE}{five_pct:.0f}%{R}     {DIM}{five_reset}{R}")

    # Line 4: 7-day rate limit (if available)
    seven_pct = seven_day.get("used_percentage")
    if seven_pct is not None:
        seven_bar = progress_bar(seven_pct)
        seven_reset = format_reset_time(seven_day.get("resets_at"))
        print(f"{BLUE}\U0001f4c5 7d{R}  {seven_bar}  {WHITE}{seven_pct:.0f}%{R}  {CYAN}\u5168\u30e2\u30c7\u30eb{R}     {DIM}{seven_reset}{R}")


if __name__ == "__main__":
    main()
