#!/usr/bin/env python3
"""Claude Code status line script.

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
    return "\u25b0" * filled + "\u25b1" * empty


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
        f"\U0001f916 {model_name}",
        f"\U0001f4c1 {project}",
        f"\U0001f33f {branch}",
        f"\U0001f5a5  {os_name}",
    ]
    print(" \u2502 ".join(line1_parts))

    # Line 2: Context % / File changes / Online
    ctx_bar = progress_bar(ctx_pct)
    line2_parts = [
        f"\U0001f4ca {ctx_pct:.0f}% {ctx_bar}",
        f"\u270f\ufe0f  +{lines_added}/-{lines_removed}",
    ]
    if duration_ms > 0:
        line2_parts.append(f"\u23f1  {format_duration(duration_ms)}")
    print(" \u2502 ".join(line2_parts))

    # Line 3: 5-hour rate limit (if available)
    five_pct = five_hour.get("used_percentage")
    if five_pct is not None:
        five_bar = progress_bar(five_pct)
        five_reset = format_reset_time(five_hour.get("resets_at"))
        print(f"\u23f1  5h  {five_bar}  {five_pct:.0f}%     {five_reset}")

    # Line 4: 7-day rate limit (if available)
    seven_pct = seven_day.get("used_percentage")
    if seven_pct is not None:
        seven_bar = progress_bar(seven_pct)
        seven_reset = format_reset_time(seven_day.get("resets_at"))
        print(f"\U0001f4c5 7d  {seven_bar}  {seven_pct:.0f}%  \u5168\u30e2\u30c7\u30eb     {seven_reset}")


if __name__ == "__main__":
    main()
