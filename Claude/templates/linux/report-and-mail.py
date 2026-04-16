#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
report-and-mail.py — ClaudeOS v3.2.0
====================================

Cron で起動された ClaudeCode セッションの結果をログから解析し、
HTML 形式のレポートメールを Gmail SMTP 経由で送信する。

Usage:
    python3 report-and-mail.py \
        --session <session_id> \
        --log <log_file_path> \
        --status <completed|failed|timeout> \
        --start <ISO8601> \
        --end <ISO8601> \
        --duration-min <minutes>

設計原則:
- Python 3 標準ライブラリのみ使用 (依存追加なし)
- SMTP 認証情報は Linux 環境変数 CLAUDEOS_SMTP_USER / CLAUDEOS_SMTP_PASS から取得
- 環境変数未設定時は警告を出して終了 (cron 全体は失敗させない)
- HTML テンプレートはアイコン + 色付き + 表形式 (Gmail で確実に表示できるインライン CSS)
- 全文字列は UTF-8、件名は MIME エンコード済
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import smtplib
import socket
import sys
from email.message import EmailMessage
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

DEFAULT_SMTP_HOST = "smtp.gmail.com"
DEFAULT_SMTP_PORT = 587
# 配布テンプレートとして実在アドレスをハードコードしない。
# 1) --to-addr / --from-addr で明示指定、または
# 2) 環境変数 CLAUDEOS_DEFAULT_TO / CLAUDEOS_DEFAULT_FROM で上書き、
# 3) 最後の fallback として CLAUDEOS_SMTP_USER (= 認証アカウント) を使う。
DEFAULT_TO = (
    os.environ.get("CLAUDEOS_DEFAULT_TO")
    or os.environ.get("CLAUDEOS_SMTP_USER")
    or ""
)
DEFAULT_FROM = (
    os.environ.get("CLAUDEOS_DEFAULT_FROM")
    or os.environ.get("CLAUDEOS_SMTP_USER")
    or ""
)
DEFAULT_SUBJECT_PREFIX = "[ClaudeOS]"

ICON = {
    "completed": "🟢",
    "failed": "🔴",
    "timeout": "🟡",
    "running": "🔵",
    "session": "🤖",
    "calendar": "📅",
    "finish": "🏁",
    "clock": "⏱",
    "folder": "📂",
    "summary": "📝",
    "next": "➡️",
    "host": "🖥",
    "log": "📜",
}

COLOR = {
    "completed": "#16a34a",  # green-600
    "failed": "#dc2626",     # red-600
    "timeout": "#ca8a04",    # yellow-600
    "running": "#2563eb",    # blue-600
    "header_bg": "#0f172a",  # slate-900
    "header_fg": "#ffffff",
    "row_bg": "#f8fafc",     # slate-50
    "row_alt_bg": "#ffffff",
    "border": "#cbd5e1",     # slate-300
    "muted": "#64748b",      # slate-500
}


# ---------------------------------------------------------------------------
# ログ解析
# ---------------------------------------------------------------------------

PHASE_PATTERNS = [
    (re.compile(r"\bMonitor\b", re.IGNORECASE), "Monitor"),
    (re.compile(r"\bDevelopment\b|\bBuild\b", re.IGNORECASE), "Development"),
    (re.compile(r"\bVerify\b", re.IGNORECASE), "Verify"),
    (re.compile(r"\bImprovement\b|\bImprove\b", re.IGNORECASE), "Improvement"),
]

ERROR_PATTERNS = [
    re.compile(r"\b(error|ERROR|Error)\b"),
    re.compile(r"\b(failed|FAILED|Failed)\b"),
    re.compile(r"\b(traceback|Traceback)\b"),
]

STABLE_PATTERN = re.compile(r"STABLE\s*(達成|achieved)", re.IGNORECASE)


def parse_log(log_path: Path) -> dict[str, Any]:
    """ログファイルから集計情報を抽出する。ファイル無し/読み込み失敗時も dict を返す。"""
    summary: dict[str, Any] = {
        "lines_total": 0,
        "phase_counts": {p[1]: 0 for p in PHASE_PATTERNS},
        "error_count": 0,
        "stable_achieved": False,
        "tail": [],
        "head": [],
    }
    if not log_path.exists():
        summary["tail"] = ["(ログファイルが見つかりません)"]
        return summary

    try:
        with log_path.open("r", encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError as exc:
        summary["tail"] = [f"(ログ読み込み失敗: {exc})"]
        return summary

    summary["lines_total"] = len(lines)
    for line in lines:
        for pat, name in PHASE_PATTERNS:
            if pat.search(line):
                summary["phase_counts"][name] += 1
                break
        for ep in ERROR_PATTERNS:
            if ep.search(line):
                summary["error_count"] += 1
                break
        if STABLE_PATTERN.search(line):
            summary["stable_achieved"] = True

    summary["head"] = [ln.rstrip() for ln in lines[:10]]
    summary["tail"] = [ln.rstrip() for ln in lines[-15:]]
    return summary


def load_session_json(session_dir: Path, session_id: str) -> dict[str, Any]:
    """session.json があれば読み込んで dict を返す。無ければ空 dict。"""
    candidate = session_dir / f"{session_id}.json"
    if not candidate.exists():
        return {}
    try:
        return json.loads(candidate.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def suggest_next_phase(parsed: dict[str, Any], status: str) -> str:
    """次フェーズの提案文を生成する。ログ集計と status から判定。"""
    if status == "failed":
        return "🔧 Repair: 失敗原因の切り分け → 最小修正 → 再 Verify"
    if status == "timeout":
        return "⏸ 中断引継ぎ: state.json 確認 → 残課題整理 → 次セッションで /recap → 続行"
    if parsed["stable_achieved"]:
        return "🚀 Release: STABLE 達成済。次は Deploy Gate / マージ判断 → 本番反映"
    if parsed["error_count"] > 0:
        return "🐛 Debug: ログにエラー痕跡あり。Codex rescue で原因分析 → 最小修正"
    if parsed["phase_counts"].get("Verify", 0) >= 1:
        return "🔬 STABLE 判定の確定: 連続成功 N=3 を満たすか確認 → Improvement へ"
    return "🔍 Monitor 再開: GitHub Projects / Issues / CI 状態確認 → 次タスク選定"


# ---------------------------------------------------------------------------
# 時刻計算
# ---------------------------------------------------------------------------

def parse_iso(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        # Python 3.11+ は fromisoformat が "+09:00" などを受け付ける
        return dt.datetime.fromisoformat(value)
    except ValueError:
        return None


def _normalize_tz(value: dt.datetime | None) -> dt.datetime | None:
    """tzinfo の有無を揃えて aware/naive 混在による TypeError を防ぐ。"""
    if value is None:
        return None
    if value.tzinfo is None:
        # naive はローカル TZ として解釈する
        return value.astimezone()
    return value


def format_duration(start: dt.datetime | None, end: dt.datetime | None) -> str:
    if not start or not end:
        return "(計測不能)"
    s = _normalize_tz(start)
    e = _normalize_tz(end)
    if s is None or e is None:
        return "(計測不能)"
    delta = e - s
    total_sec = int(delta.total_seconds())
    if total_sec < 0:
        return "(時刻順不整合)"
    hours, rem = divmod(total_sec, 3600)
    minutes, seconds = divmod(rem, 60)
    return f"{hours} 時間 {minutes} 分 {seconds} 秒"


def fmt_dt(value: dt.datetime | None) -> str:
    if not value:
        return "(不明)"
    return value.strftime("%Y-%m-%d %H:%M:%S")


# ---------------------------------------------------------------------------
# HTML レンダリング
# ---------------------------------------------------------------------------

def render_html(ctx: dict[str, Any]) -> str:
    status = ctx["status"]
    status_color = COLOR.get(status, COLOR["muted"])
    status_icon = ICON.get(status, "⚪")

    parsed = ctx["parsed"]
    rows = [
        ("ステータス", f"{status_icon} <strong style=\"color:{status_color}\">{status}</strong>"),
        ("プロジェクト", f"{ICON['folder']} {html_escape(ctx['project'])}"),
        ("セッション ID", f"{ICON['session']} <code>{html_escape(ctx['session_id'])}</code>"),
        ("ホスト", f"{ICON['host']} {html_escape(ctx['hostname'])}"),
        ("開始", f"{ICON['calendar']} {html_escape(ctx['start_str'])}"),
        ("終了", f"{ICON['finish']} {html_escape(ctx['end_str'])}"),
        ("総作業時間", f"{ICON['clock']} <strong>{html_escape(ctx['duration_str'])}</strong>"),
        ("予定時間", f"{ICON['clock']} {ctx['duration_min']} 分"),
        ("ログファイル", f"{ICON['log']} <code>{html_escape(ctx['log_path'])}</code>"),
    ]

    rows_html = "\n".join(
        f'<tr style="background:{COLOR["row_bg"] if i % 2 == 0 else COLOR["row_alt_bg"]}">'
        f'<th align="left" style="padding:8px 12px;border:1px solid {COLOR["border"]};width:32%">{label}</th>'
        f'<td style="padding:8px 12px;border:1px solid {COLOR["border"]}">{value}</td>'
        f"</tr>"
        for i, (label, value) in enumerate(rows)
    )

    phase_rows = "\n".join(
        f'<tr><td style="padding:6px 12px;border:1px solid {COLOR["border"]}">{phase}</td>'
        f'<td align="right" style="padding:6px 12px;border:1px solid {COLOR["border"]}">{count}</td></tr>'
        for phase, count in parsed["phase_counts"].items()
    )

    tail_html = "<br>".join(html_escape(ln) for ln in parsed["tail"]) or "(ログ末尾なし)"

    return f"""<!DOCTYPE html>
<html lang="ja"><head>
<meta charset="UTF-8">
<title>{html_escape(ctx['subject'])}</title>
</head>
<body style="font-family:'Segoe UI','Hiragino Kaku Gothic ProN','Yu Gothic UI',sans-serif;
             color:#0f172a;background:#f1f5f9;margin:0;padding:20px">
  <div style="max-width:760px;margin:0 auto;background:#ffffff;
              border:1px solid {COLOR['border']};border-radius:8px;overflow:hidden">

    <div style="background:{COLOR['header_bg']};color:{COLOR['header_fg']};
                padding:18px 20px">
      <div style="font-size:18px;font-weight:bold">
        {ICON['session']} ClaudeOS Cron セッション完了報告
      </div>
      <div style="font-size:12px;color:#cbd5e1;margin-top:4px">
        {html_escape(ctx['subject'])}
      </div>
    </div>

    <div style="padding:20px">
      <table cellpadding="0" cellspacing="0"
             style="width:100%;border-collapse:collapse;font-size:14px">
        {rows_html}
      </table>

      <h3 style="margin-top:24px;border-left:4px solid {status_color};padding-left:8px">
        {ICON['summary']} 実行サマリー
      </h3>
      <table cellpadding="0" cellspacing="0"
             style="border-collapse:collapse;font-size:13px;margin-top:8px">
        <thead>
          <tr style="background:{COLOR['row_bg']}">
            <th align="left" style="padding:6px 12px;border:1px solid {COLOR['border']}">フェーズ</th>
            <th align="right" style="padding:6px 12px;border:1px solid {COLOR['border']}">出現回数</th>
          </tr>
        </thead>
        <tbody>
          {phase_rows}
          <tr style="background:#fef2f2">
            <td style="padding:6px 12px;border:1px solid {COLOR['border']}">エラー検出</td>
            <td align="right" style="padding:6px 12px;border:1px solid {COLOR['border']};
                                     color:{'#dc2626' if parsed['error_count'] > 0 else '#16a34a'};
                                     font-weight:bold">
              {parsed['error_count']}
            </td>
          </tr>
          <tr>
            <td style="padding:6px 12px;border:1px solid {COLOR['border']}">ログ総行数</td>
            <td align="right" style="padding:6px 12px;border:1px solid {COLOR['border']}">
              {parsed['lines_total']:,}
            </td>
          </tr>
          <tr>
            <td style="padding:6px 12px;border:1px solid {COLOR['border']}">STABLE 達成</td>
            <td align="right" style="padding:6px 12px;border:1px solid {COLOR['border']};
                                     color:{'#16a34a' if parsed['stable_achieved'] else COLOR['muted']};
                                     font-weight:bold">
              {'はい' if parsed['stable_achieved'] else 'いいえ'}
            </td>
          </tr>
        </tbody>
      </table>

      <h3 style="margin-top:24px;border-left:4px solid {status_color};padding-left:8px">
        {ICON['log']} ログ末尾(最後の 15 行)
      </h3>
      <pre style="background:#0f172a;color:#e2e8f0;padding:12px;border-radius:4px;
                  font-size:12px;line-height:1.5;overflow-x:auto;
                  white-space:pre-wrap;word-break:break-all">{tail_html}</pre>

      <h3 style="margin-top:24px;border-left:4px solid {status_color};padding-left:8px">
        {ICON['next']} 次の開発フェーズ提案
      </h3>
      <div style="padding:12px 16px;background:#f0f9ff;border:1px solid #bae6fd;
                  border-radius:6px;font-size:14px">
        {html_escape(ctx['next_phase'])}
      </div>

      <div style="margin-top:24px;padding-top:12px;border-top:1px solid {COLOR['border']};
                  font-size:11px;color:{COLOR['muted']}">
        Generated by ClaudeOS v3.2.0 report-and-mail.py · {html_escape(ctx['generated_at'])}
      </div>
    </div>
  </div>
</body></html>
"""


def render_text(ctx: dict[str, Any]) -> str:
    """HTML を表示できないクライアント向けの plain text 版。"""
    parsed = ctx["parsed"]
    lines = [
        f"[ClaudeOS Cron] {ctx['status']} — {ctx['project']}",
        "",
        f"Session  : {ctx['session_id']}",
        f"Host     : {ctx['hostname']}",
        f"Project  : {ctx['project']}",
        f"Status   : {ctx['status']}",
        f"Start    : {ctx['start_str']}",
        f"End      : {ctx['end_str']}",
        f"Duration : {ctx['duration_str']}",
        f"Log      : {ctx['log_path']}",
        "",
        "--- Phase counts ---",
    ]
    for phase, count in parsed["phase_counts"].items():
        lines.append(f"  {phase:<14} {count}")
    lines.append(f"  Errors        {parsed['error_count']}")
    lines.append(f"  Log lines     {parsed['lines_total']}")
    lines.append(f"  STABLE        {'yes' if parsed['stable_achieved'] else 'no'}")
    lines.append("")
    lines.append("--- Log tail ---")
    lines.extend(parsed["tail"])
    lines.append("")
    lines.append("--- Next phase ---")
    lines.append(ctx["next_phase"])
    return "\n".join(lines)


def html_escape(value: Any) -> str:
    text = "" if value is None else str(value)
    return (
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&#39;")
    )


# ---------------------------------------------------------------------------
# SMTP 送信
# ---------------------------------------------------------------------------

def send_mail(
    *,
    smtp_host: str,
    smtp_port: int,
    user: str,
    password: str,
    sender: str,
    recipient: str,
    subject: str,
    text_body: str,
    html_body: str,
    timeout: int = 20,
) -> None:
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = sender
    msg["To"] = recipient
    msg.set_content(text_body, charset="utf-8")
    msg.add_alternative(html_body, subtype="html", charset="utf-8")

    with smtplib.SMTP(smtp_host, smtp_port, timeout=timeout) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()
        server.login(user, password)
        server.send_message(msg)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="ClaudeOS cron session HTML report mailer"
    )
    parser.add_argument("--session", required=True, help="session id")
    parser.add_argument("--log", required=True, help="log file path")
    parser.add_argument("--status", required=True,
                        choices=["completed", "failed", "timeout", "running"])
    parser.add_argument("--start", default="", help="ISO8601 start time")
    parser.add_argument("--end", default="", help="ISO8601 end time")
    parser.add_argument("--duration-min", type=int, default=0,
                        help="planned duration in minutes")
    parser.add_argument("--project", default=os.environ.get("CLAUDE_PROJECT", ""),
                        help="project name")
    parser.add_argument("--sessions-dir",
                        default=os.path.expanduser("~/.claudeos/sessions"))
    parser.add_argument("--smtp-host", default=DEFAULT_SMTP_HOST)
    parser.add_argument("--smtp-port", type=int, default=DEFAULT_SMTP_PORT)
    parser.add_argument("--from-addr", default=DEFAULT_FROM)
    parser.add_argument("--to-addr", default=DEFAULT_TO)
    parser.add_argument("--subject-prefix", default=DEFAULT_SUBJECT_PREFIX)
    parser.add_argument("--dry-run", action="store_true",
                        help="送信せず HTML を stdout に出力")
    args = parser.parse_args()

    user_env = os.environ.get("CLAUDEOS_SMTP_USER", "")
    pass_env = os.environ.get("CLAUDEOS_SMTP_PASS", "")
    if not args.dry_run and (not user_env or not pass_env):
        sys.stderr.write(
            "[report-and-mail] WARN: CLAUDEOS_SMTP_USER / CLAUDEOS_SMTP_PASS "
            "が未設定のためメール送信をスキップ。\n"
        )
        return 0

    if not args.dry_run and (not args.to_addr or not args.from_addr):
        sys.stderr.write(
            "[report-and-mail] WARN: --to-addr / --from-addr 未指定 "
            "(CLAUDEOS_DEFAULT_TO / CLAUDEOS_DEFAULT_FROM / CLAUDEOS_SMTP_USER のいずれかで設定)。\n"
        )
        return 0

    log_path = Path(args.log)
    parsed = parse_log(log_path)
    sess_meta = load_session_json(Path(args.sessions_dir), args.session)

    project = args.project or sess_meta.get("project") or "(unknown)"
    start_dt = parse_iso(args.start) or parse_iso(sess_meta.get("start_time", ""))
    end_dt = parse_iso(args.end) or dt.datetime.now().astimezone()
    next_phase = suggest_next_phase(parsed, args.status)

    ctx: dict[str, Any] = {
        "session_id": args.session,
        "project": project,
        "status": args.status,
        "hostname": socket.gethostname(),
        "start_str": fmt_dt(start_dt),
        "end_str": fmt_dt(end_dt),
        "duration_str": format_duration(start_dt, end_dt),
        "duration_min": args.duration_min,
        "log_path": str(log_path),
        "parsed": parsed,
        "next_phase": next_phase,
        "generated_at": dt.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z"),
        "subject": (
            f"{args.subject_prefix} {ICON.get(args.status, '⚪')} "
            f"{args.status} — {project} ({args.session})"
        ),
    }

    html_body = render_html(ctx)
    text_body = render_text(ctx)

    if args.dry_run:
        # 絵文字を含む HTML を確実に UTF-8 で出力する。
        # Windows の cp932 stdout でも UnicodeEncodeError を起こさないよう
        # buffer に直接バイト列を書き込む (Linux でも同等に動作)。
        sys.stdout.buffer.write(html_body.encode("utf-8"))
        return 0

    try:
        send_mail(
            smtp_host=args.smtp_host,
            smtp_port=args.smtp_port,
            user=user_env,
            password=pass_env,
            sender=args.from_addr,
            recipient=args.to_addr,
            subject=ctx["subject"],
            text_body=text_body,
            html_body=html_body,
        )
        sys.stderr.write(
            f"[report-and-mail] sent → {args.to_addr} (session={args.session})\n"
        )
        return 0
    except (smtplib.SMTPException, OSError) as exc:
        # SMTP 送信失敗は cron 全体を失敗にしないため exit 0
        sys.stderr.write(f"[report-and-mail] send failed: {exc}\n")
        return 0


if __name__ == "__main__":
    sys.exit(main())
