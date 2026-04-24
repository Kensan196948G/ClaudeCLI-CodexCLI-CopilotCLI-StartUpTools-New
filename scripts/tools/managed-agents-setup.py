#!/usr/bin/env python3
"""
managed-agents-setup.py — Anthropic Managed Agents: エージェント定義とオーケストレーター構築
CLAUDE.md の Agent Teams（CTO/Architect/Developer/QA/Security/DevOps/Reviewer）を
Managed Agents API の callable_agents 構造として API 上に実体化する。

Usage:
  python managed-agents-setup.py status
  python managed-agents-setup.py create-environment [--name NAME]
  python managed-agents-setup.py create-agents [--env-id ID]
  python managed-agents-setup.py create-orchestrator [--env-id ID]
  python managed-agents-setup.py setup-all          # 上記3つをまとめて実行
  python managed-agents-setup.py list-agents
  python managed-agents-setup.py delete-all         # クリーンアップ (要確認)

Config: config/managed-agents.json (gitignored)
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
from pathlib import Path
from typing import Any

# Windows CP932 端末での日本語文字エンコードエラーを防ぐ
if hasattr(sys.stdout, "buffer"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "buffer"):
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ── パス定数 ─────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
CONFIG_FILE = PROJECT_ROOT / "config" / "managed-agents.json"

MODEL_ORCHESTRATOR = "claude-opus-4-7"
MODEL_SPECIALIST = "claude-sonnet-4-6"

# ── Agent Teams ロール定義（CLAUDE.md の § 6 と対応） ─────────────────────────
SPECIALIST_AGENTS = [
    {
        "key": "architect",
        "name": "ClaudeOS-Architect",
        "model": MODEL_SPECIALIST,
        "system": (
            "You are an Architect agent in the ClaudeOS autonomous development organization.\n"
            "Responsibilities: system design, architecture review, responsibility separation, "
            "structure improvement, design memos.\n"
            "Output format: concise Markdown decisions with rationale. "
            "Flag design risks explicitly. Do not implement — delegate to Developer."
        ),
    },
    {
        "key": "developer",
        "name": "ClaudeOS-Developer",
        "model": MODEL_SPECIALIST,
        "system": (
            "You are a Developer agent in the ClaudeOS autonomous development organization.\n"
            "Responsibilities: implementation, bug fixes, repairs, configuration changes, "
            "WorkTree operations.\n"
            "Always write tests alongside implementation. "
            "Follow the branch naming convention: fix/<issue> or feat/<issue>. "
            "Never push directly to main."
        ),
    },
    {
        "key": "qa",
        "name": "ClaudeOS-QA",
        "model": MODEL_SPECIALIST,
        "system": (
            "You are a QA agent in the ClaudeOS autonomous development organization.\n"
            "Responsibilities: test writing, regression verification, quality evaluation, "
            "Pester/Jest/E2E test execution.\n"
            "STABLE criteria: test success + lint success + build success + CI success "
            "+ review OK + security OK + error 0.\n"
            "Report pass/fail counts and first failure details. "
            "Do NOT modify production code — raise issues instead."
        ),
    },
    {
        "key": "security",
        "name": "ClaudeOS-Security",
        "model": MODEL_SPECIALIST,
        "system": (
            "You are a Security agent in the ClaudeOS autonomous development organization.\n"
            "Responsibilities: secret scanning, permission review, vulnerability assessment, "
            "risk evaluation for auth/DB/parallel-processing changes.\n"
            "Classify findings as P1/P2/P3. P1 findings block merge. "
            "Output structured JSON: {finding, severity, file, line, recommendation}."
        ),
    },
    {
        "key": "devops",
        "name": "ClaudeOS-DevOps",
        "model": MODEL_SPECIALIST,
        "system": (
            "You are a DevOps agent in the ClaudeOS autonomous development organization.\n"
            "Responsibilities: CI/CD management, PR creation, GitHub Projects update, "
            "deploy gate control, WorkTree cleanup.\n"
            "GitHub Projects states: Inbox → Backlog → Ready → Design → Development "
            "→ Verify → Deploy Gate → Done / Blocked.\n"
            "Report CI status as JSON: {workflow, status, run_id, conclusion}."
        ),
    },
    {
        "key": "reviewer",
        "name": "ClaudeOS-Reviewer",
        "model": MODEL_SPECIALIST,
        "system": (
            "You are a Reviewer agent in the ClaudeOS autonomous development organization.\n"
            "Responsibilities: code quality review, maintainability, naming conventions, "
            "diff verification, CodeRabbit result integration.\n"
            "Severity levels: Critical/High (block merge) | Medium (fix recommended) | "
            "Low (optional). Output: per-file comment list with severity and line reference."
        ),
    },
]

ORCHESTRATOR_DEF = {
    "key": "cto",
    "name": "ClaudeOS-CTO-Orchestrator",
    "model": MODEL_ORCHESTRATOR,
    "system": (
        "You are the CTO Orchestrator of the ClaudeOS autonomous development organization.\n\n"
        "## Mission\n"
        "Coordinate the Monitor → Build → Verify → Improve development loop autonomously.\n"
        "You have full authority (CTO全権委任). Never ask for permission — make decisions.\n\n"
        "## Loop phases\n"
        "- Monitor (30m): Confirm GitHub/CI/Issues state. Decompose tasks.\n"
        "- Build (2h): Design + implementation via Architect and Developer agents.\n"
        "- Verify (1h15m): Tests + lint + CI via QA, Security, DevOps agents.\n"
        "- Improve (1h15m): Refactoring + docs + README via Reviewer and Developer.\n\n"
        "## STABLE judgment\n"
        "STABLE = test✓ + lint✓ + build✓ + CI✓ + review✓ + security✓ + error=0\n"
        "Never merge without STABLE. Auto-repair up to 15 retries; block after 3 same errors.\n\n"
        "## Delegation rules\n"
        "- Architecture decisions → Architect agent\n"
        "- Implementation/fixes → Developer agent\n"
        "- Test/quality checks → QA agent\n"
        "- Security review → Security agent\n"
        "- CI/PR/Projects → DevOps agent\n"
        "- Code review → Reviewer agent\n\n"
        "## Output format\n"
        "[CTO] decision: <one-line decision>\n"
        "delegating to: <agent_name> | reason: <reason>\n"
        "next_phase: <Monitor|Build|Verify|Improve>"
    ),
}


# ── 共通ユーティリティ ─────────────────────────────────────────────────────────

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


# ── サブコマンド ──────────────────────────────────────────────────────────────

def cmd_status(args: argparse.Namespace) -> None:
    cfg = load_config()
    api_key = os.environ.get("ANTHROPIC_API_KEY") or cfg.get("apiKey", "")
    status = {
        "api_key_set": bool(api_key),
        "environment_id": cfg.get("environmentId"),
        "orchestrator_id": cfg.get("orchestratorId"),
        "specialist_agents": cfg.get("specialistAgents", {}),
        "config_file": str(CONFIG_FILE),
        "ready_for_session": bool(
            api_key
            and cfg.get("environmentId")
            and cfg.get("orchestratorId")
        ),
    }
    _out(status)


def cmd_create_environment(args: argparse.Namespace) -> None:
    client = get_client()
    name = args.name or "ClaudeOS-Environment"

    env = client.beta.environments.create(name=name)
    cfg = load_config()
    cfg["environmentId"] = env.id
    save_config(cfg)

    _out({
        "success": True,
        "environment_id": env.id,
        "name": getattr(env, "name", name),
        "message": "environment_id を config に保存しました。",
    })


def _build_agent_tools(include_github_mcp: bool = False) -> list:
    tools: list = [{"type": "agent_toolset_20260401"}]
    if include_github_mcp:
        tools.append({"type": "mcp_toolset", "mcp_server_name": "github"})
    return tools


def cmd_create_agents(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()

    specialist_ids: dict = cfg.get("specialistAgents", {})
    created = []

    for spec in SPECIALIST_AGENTS:
        try:
            agent = client.beta.agents.create(
                name=spec["name"],
                model=spec["model"],
                system=spec["system"],
                tools=_build_agent_tools(),
            )
            specialist_ids[spec["key"]] = {
                "id": agent.id,
                "version": getattr(agent, "version", 1),
                "name": spec["name"],
            }
            created.append({"key": spec["key"], "id": agent.id, "status": "created"})
        except Exception as e:
            created.append({"key": spec["key"], "status": "error", "error": str(e)})

    cfg["specialistAgents"] = specialist_ids
    save_config(cfg)

    _out({
        "success": True,
        "created": created,
        "specialist_ids": specialist_ids,
    })


def cmd_create_orchestrator(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()

    specialist_agents = cfg.get("specialistAgents", {})
    if not specialist_agents:
        _die("専門エージェントが未作成です。先に create-agents を実行してください。")

    # callable_agents リストを構築
    callable_agents = []
    for key, info in specialist_agents.items():
        callable_agents.append({
            "type": "agent",
            "id": info["id"],
            "version": info.get("version", 1),
        })

    # Memory Store をシステムプロンプトに指示として追加
    memory_store_id = cfg.get("memoryStoreId")
    system = ORCHESTRATOR_DEF["system"]
    if memory_store_id:
        system += (
            f"\n\n## Memory Store\n"
            f"Store ID: {memory_store_id}\n"
            "セッション開始時は /memory/ ディレクトリを確認して前回の文脈を引き継ぐこと。"
        )

    # callable_agents は Multi-agent Research Preview 機能のため extra_body で渡す
    orchestrator = client.beta.agents.create(
        name=ORCHESTRATOR_DEF["name"],
        model=ORCHESTRATOR_DEF["model"],
        system=system,
        tools=_build_agent_tools(include_github_mcp=False),
        extra_body={"callable_agents": callable_agents},
    )

    cfg["orchestratorId"] = orchestrator.id
    cfg["orchestratorVersion"] = getattr(orchestrator, "version", 1)
    save_config(cfg)

    _out({
        "success": True,
        "orchestrator_id": orchestrator.id,
        "orchestrator_version": getattr(orchestrator, "version", 1),
        "callable_agents_count": len(callable_agents),
        "callable_agents": [a["id"] for a in callable_agents],
        "message": "orchestrator_id を config に保存しました。",
    })


def cmd_setup_all(args: argparse.Namespace) -> None:
    """create-environment → create-agents → create-orchestrator を順に実行。"""
    print("# Step 1/3: Environment 作成", file=sys.stderr)
    cmd_create_environment(argparse.Namespace(name=""))

    print("# Step 2/3: Specialist Agents 作成", file=sys.stderr)
    cmd_create_agents(argparse.Namespace())

    print("# Step 3/3: CTO Orchestrator 作成", file=sys.stderr)
    cmd_create_orchestrator(argparse.Namespace())

    # 最終サマリー
    cfg = load_config()
    _out({
        "setup_complete": True,
        "environment_id": cfg.get("environmentId"),
        "orchestrator_id": cfg.get("orchestratorId"),
        "specialist_count": len(cfg.get("specialistAgents", {})),
        "next_step": "python managed-session.py run --task '...'",
    })


def cmd_list_agents(args: argparse.Namespace) -> None:
    client = get_client()
    agents = []
    for agent in client.beta.agents.list():
        agents.append({
            "id": agent.id,
            "name": agent.name,
            "model": getattr(agent, "model", ""),
            "version": getattr(agent, "version", ""),
        })
    _out({"count": len(agents), "agents": agents})


def cmd_delete_all(args: argparse.Namespace) -> None:
    """登録済みの全エージェントと環境を削除する（確認プロンプトあり）。"""
    cfg = load_config()
    client = get_client()

    if not args.yes:
        confirm = input("全エージェントを削除しますか？ (yes/no): ").strip()
        if confirm.lower() != "yes":
            print("キャンセルしました。")
            return

    deleted = []
    for key, info in cfg.get("specialistAgents", {}).items():
        try:
            client.beta.agents.delete(info["id"])
            deleted.append({"key": key, "id": info["id"], "status": "deleted"})
        except Exception as e:
            deleted.append({"key": key, "id": info["id"], "status": "error", "error": str(e)})

    if cfg.get("orchestratorId"):
        try:
            client.beta.agents.delete(cfg["orchestratorId"])
            deleted.append({"key": "cto_orchestrator", "id": cfg["orchestratorId"], "status": "deleted"})
        except Exception as e:
            deleted.append({"key": "cto_orchestrator", "status": "error", "error": str(e)})

    cfg.pop("specialistAgents", None)
    cfg.pop("orchestratorId", None)
    cfg.pop("orchestratorVersion", None)
    cfg.pop("environmentId", None)
    save_config(cfg)

    _out({"deleted": deleted, "config_cleared": True})


# ── CLI エントリーポイント ────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Managed Agents セットアップ CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("status", help="現在の設定状態を確認")

    p = sub.add_parser("create-environment", help="実行環境を作成")
    p.add_argument("--name", default="")

    sub.add_parser("create-agents", help="専門エージェント 6 体を作成")

    sub.add_parser("create-orchestrator", help="CTO オーケストレーターを作成")

    sub.add_parser("setup-all", help="環境+エージェント+オーケストレーターを一括作成")

    sub.add_parser("list-agents", help="API 上のエージェント一覧")

    p = sub.add_parser("delete-all", help="全エージェントを削除（クリーンアップ）")
    p.add_argument("--yes", action="store_true", help="確認なしで実行")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    dispatch = {
        "status": cmd_status,
        "create-environment": cmd_create_environment,
        "create-agents": cmd_create_agents,
        "create-orchestrator": cmd_create_orchestrator,
        "setup-all": cmd_setup_all,
        "list-agents": cmd_list_agents,
        "delete-all": cmd_delete_all,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
