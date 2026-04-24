#!/usr/bin/env python3
"""
managed-session.py — Anthropic Managed Agents セッション実行・ストリーミング
Monitor→Build→Verify→Improve ループの各フェーズをセッションとして実行する。

Usage:
  python managed-session.py run --task "Monitor: CI/GitHub 状態を確認する"
  python managed-session.py run --phase monitor
  python managed-session.py run --phase build --task "Issue #239 の実装を進める"
  python managed-session.py list
  python managed-session.py status --session-id sesn_...
  python managed-session.py stream --session-id sesn_...

Config: config/managed-agents.json (orchestratorId, environmentId, memoryStoreId)
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

# Windows CP932 端末での日本語文字エンコードエラーを防ぐ
if hasattr(sys.stdout, "buffer"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "buffer"):
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
CONFIG_FILE = PROJECT_ROOT / "config" / "managed-agents.json"
MEMORY_DIR = (
    Path.home()
    / ".claude"
    / "projects"
    / "D--ClaudeCode-StartUpTools-New"
    / "memory"
)

# フェーズごとのデフォルトタスク
PHASE_TASKS = {
    "monitor": (
        "Monitor フェーズを実行してください。\n"
        "1. GitHub Projects / Issues / CI の状態を確認\n"
        "2. 未解決の P1/P2 Issue を洗い出す\n"
        "3. 次の Build フェーズのタスクを 3 点に絞る\n"
        "4. state.json の goal/kpi を確認して方針を決定する\n"
        "結果は JSON 形式で: {phase, issues_found, next_tasks, ci_status}"
    ),
    "build": (
        "Build フェーズを実行してください。\n"
        "1. Monitor フェーズの next_tasks を確認\n"
        "2. Architect に設計を依頼する\n"
        "3. Developer に実装を依頼する\n"
        "4. 変更は必ずブランチを作成して行う（main 直 push 禁止）\n"
        "5. 実装が完了したら QA に渡す"
    ),
    "verify": (
        "Verify フェーズを実行してください。\n"
        "1. QA にテスト実行を依頼する\n"
        "2. Security に変更箇所の脆弱性確認を依頼する\n"
        "3. DevOps に CI ステータスを確認させる\n"
        "4. Reviewer にコードレビューを依頼する\n"
        "5. STABLE 判定（test✓ lint✓ build✓ CI✓ review✓ security✓ error=0）を実施\n"
        "結果は JSON 形式で: {stable, issues, next_action}"
    ),
    "improve": (
        "Improve フェーズを実行してください。\n"
        "1. Reviewer に命名/リファクタリング改善提案を依頼する\n"
        "2. Developer に軽微な改善を実施させる\n"
        "3. README.md と docs を最新状態に更新する\n"
        "4. GitHub Projects のステータスを更新する\n"
        "5. 次セッションの再開ポイントをメモリに保存する"
    ),
}


def load_config() -> dict:
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text(encoding="utf-8-sig"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return {}
    return {}


def save_config(cfg: dict) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(
        json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def get_client():
    import anthropic
    key = os.environ.get("ANTHROPIC_API_KEY") or load_config().get("apiKey", "")
    if not key:
        _die("ANTHROPIC_API_KEY が未設定です。Setup-ManagedAgents.ps1 を実行してください。")
    return anthropic.Anthropic(api_key=key)


def _die(msg: str) -> None:
    print(json.dumps({"error": msg}, ensure_ascii=False), file=sys.stderr)
    sys.exit(1)


def _out(data: Any) -> None:
    print(json.dumps(data, indent=2, ensure_ascii=False))


def _build_session_resources(cfg: dict) -> list:
    """Memory Store を resources として組み立てる。"""
    resources = []
    if cfg.get("memoryStoreId"):
        resources.append({
            "type": "memory_store",
            "memory_store_id": cfg["memoryStoreId"],
            "access": "read_write",
            "instructions": (
                "ClaudeOS のセッション横断記憶。"
                "/feedback/, /project/, /user/, /reference/ に分類されたメモリを保持。"
                "タスク開始前に関連メモリを確認し、タスク完了後に学習内容を書き込むこと。"
            ),
        })
    return resources


def cmd_run(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()

    orchestrator_id = cfg.get("orchestratorId")
    environment_id = cfg.get("environmentId")

    if not orchestrator_id:
        _die("orchestratorId が未設定です。managed-agents-setup.py setup-all を実行してください。")
    if not environment_id:
        _die("environmentId が未設定です。managed-agents-setup.py create-environment を実行してください。")

    # タスク文字列を決定
    phase = (args.phase or "").lower()
    task = args.task or PHASE_TASKS.get(phase, "")
    if not task:
        _die(f"--task か --phase (monitor/build/verify/improve) を指定してください。")

    resources = _build_session_resources(cfg)

    # セッション作成
    session_params: dict = {
        "agent": orchestrator_id,
        "environment_id": environment_id,
        "title": f"ClaudeOS {phase.upper() or 'Session'}: {task[:60]}",
    }
    if resources:
        session_params["resources"] = resources

    session = client.beta.sessions.create(**session_params)
    session_id = session.id

    # 最新セッション ID を保存
    cfg["lastSessionId"] = session_id
    save_config(cfg)

    print(json.dumps({"session_created": session_id, "phase": phase}, ensure_ascii=False), file=sys.stderr)

    # ユーザーメッセージを送信
    client.beta.sessions.events.send(
        session_id,
        events=[{
            "type": "user.message",
            "content": [{"type": "text", "text": task}],
        }],
    )

    # イベントをストリームして表示
    _stream_session(client, session_id, verbose=args.verbose)


def _stream_session(client, session_id: str, verbose: bool = False) -> None:
    """セッションのイベントストリームを受信して表示する。"""
    print(f"\n{'='*60}", file=sys.stderr)
    print(f"Session: {session_id}", file=sys.stderr)
    print(f"{'='*60}\n", file=sys.stderr)

    events_received = []
    try:
        with client.beta.sessions.with_streaming_response.stream_events(session_id) as stream:
            for event in stream.iter_lines():
                if not event.startswith("data:"):
                    continue
                raw = event[5:].strip()
                if not raw or raw == "[DONE]":
                    continue
                try:
                    evt = json.loads(raw)
                except json.JSONDecodeError:
                    continue

                evt_type = evt.get("type", "")
                events_received.append(evt_type)

                if evt_type == "agent.message":
                    for block in evt.get("content", []):
                        if block.get("type") == "text":
                            print(block["text"], end="", flush=True)

                elif evt_type == "agent.thinking" and verbose:
                    print(f"\n[thinking] {evt.get('thinking', '')[:200]}", file=sys.stderr)

                elif evt_type == "agent.tool_use" and verbose:
                    print(f"\n[tool] {evt.get('name', '')}({json.dumps(evt.get('input', {}))[:100]})", file=sys.stderr)

                elif evt_type == "session.thread_created":
                    print(f"\n[→ spawned thread: {evt.get('model', '')}]", file=sys.stderr)

                elif evt_type in ("session.idle", "session.terminated"):
                    print(f"\n[session {evt_type}]", file=sys.stderr)
                    break

    except AttributeError:
        # SDK がストリーミングをサポートしない場合はポーリングにフォールバック
        _poll_session(client, session_id, verbose)

    print()
    if verbose:
        print(f"\n[events received: {len(events_received)}]", file=sys.stderr)


def _poll_session(client, session_id: str, verbose: bool = False) -> None:
    """ストリーミング非対応時のポーリングフォールバック。"""
    print("[polling mode]", file=sys.stderr)
    max_polls = 120
    for i in range(max_polls):
        time.sleep(3)
        try:
            session = client.beta.sessions.retrieve(session_id)
            status = getattr(session, "status", "unknown")
            if verbose:
                print(f"[poll {i+1}] status={status}", file=sys.stderr)
            if status in ("idle", "terminated"):
                # 完了後にイベント履歴を取得
                try:
                    for evt in client.beta.sessions.events.list(session_id):
                        if getattr(evt, "type", "") == "agent.message":
                            for block in getattr(evt, "content", []):
                                if getattr(block, "type", "") == "text":
                                    print(getattr(block, "text", ""), end="")
                except Exception:
                    pass
                break
        except Exception as e:
            print(f"[poll error] {e}", file=sys.stderr)
            break


def cmd_list(args: argparse.Namespace) -> None:
    client = get_client()
    sessions = []
    for session in client.beta.sessions.list():
        sessions.append({
            "id": session.id,
            "status": getattr(session, "status", ""),
            "title": getattr(session, "title", ""),
            "created_at": str(getattr(session, "created_at", "")),
        })
    _out({"count": len(sessions), "sessions": sessions})


def cmd_status(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()
    session_id = args.session_id or cfg.get("lastSessionId")
    if not session_id:
        _die("--session-id か lastSessionId (config) が必要です。")

    session = client.beta.sessions.retrieve(session_id)

    info: dict = {
        "id": session.id,
        "status": getattr(session, "status", ""),
        "title": getattr(session, "title", ""),
        "created_at": str(getattr(session, "created_at", "")),
    }

    # スレッド情報を追加（マルチエージェント）
    try:
        threads = []
        for thread in client.beta.sessions.threads.list(session_id):
            threads.append({
                "id": thread.id,
                "agent_name": getattr(thread, "agent_name", ""),
                "status": getattr(thread, "status", ""),
            })
        info["threads"] = threads
    except Exception:
        pass

    _out(info)


def cmd_stream(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()
    session_id = args.session_id or cfg.get("lastSessionId")
    if not session_id:
        _die("--session-id か lastSessionId (config) が必要です。")

    _stream_session(client, session_id, verbose=args.verbose)


# ── CLI エントリーポイント ────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Managed Agents セッション実行 CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("run", help="セッションを作成してタスクを実行")
    p.add_argument("--task", default="", help="タスク説明（省略時はフェーズのデフォルト）")
    p.add_argument("--phase", default="", choices=["monitor", "build", "verify", "improve", ""],
                   help="ループフェーズ（--task を省略した場合のデフォルトタスクを決定）")
    p.add_argument("--verbose", "-v", action="store_true", help="ツール呼び出しも表示")

    sub.add_parser("list", help="セッション一覧")

    p = sub.add_parser("status", help="セッション状態を確認")
    p.add_argument("--session-id", default="")

    p = sub.add_parser("stream", help="既存セッションのイベントをストリーム表示")
    p.add_argument("--session-id", default="")
    p.add_argument("--verbose", "-v", action="store_true")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    dispatch = {
        "run": cmd_run,
        "list": cmd_list,
        "status": cmd_status,
        "stream": cmd_stream,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
