#!/usr/bin/env python3
"""
managed-memory.py — Anthropic Managed Agents Memory Store API client
File-based memory (~/.claude/projects/.../memory/*.md) をサーバー側 Memory Store に置き換える。

Usage:
  python managed-memory.py status
  python managed-memory.py create-store [--name NAME] [--description DESC]
  python managed-memory.py migrate [--store-id ID] [--memory-dir PATH]
  python managed-memory.py list [--store-id ID]
  python managed-memory.py read --path /feedback/x.md [--store-id ID]
  python managed-memory.py write --path /feedback/x.md --content TEXT [--store-id ID]
  python managed-memory.py sync [--store-id ID] [--memory-dir PATH] [--direction push|pull]

Config: config/managed-agents.json (gitignored)  →  apiKey, memoryStoreId
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
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


def _get_memory_dir() -> Path:
    """OS とプロジェクト絶対パスから Claude Code のメモリディレクトリを自動解決する。

    環境変数 MANAGED_MEMORY_DIR を設定すると上書き可能。
    Claude Code のプロジェクト ID 生成ルール:
      Windows: D:\\foo → D--foo  (コロン・バックスラッシュ → ハイフン)
      Linux:   /home/user/foo → -home-user-foo  (スラッシュ → ハイフン)
    """
    if env_dir := os.environ.get("MANAGED_MEMORY_DIR"):
        return Path(env_dir)

    abs_path = str(PROJECT_ROOT.resolve())
    if sys.platform == "win32":
        project_id = abs_path.replace(":", "-").replace("\\", "-").replace("/", "-").lstrip("-")
    else:
        project_id = abs_path.replace("/", "-")

    return Path.home() / ".claude" / "projects" / project_id / "memory"


MEMORY_DIR = _get_memory_dir()

STORE_NAME = "ClaudeOS-Memory"
STORE_DESC = (
    "ClaudeCode-StartUpTools-New のセッション横断記憶。"
    "feedback / project / user / reference の 4 種を管理。"
    "各メモリは Markdown + YAML frontmatter 形式。"
)


# ── 設定 I/O ──────────────────────────────────────────────────────────────────

def load_config() -> dict:
    if CONFIG_FILE.exists():
        try:
            # utf-8-sig: BOM あり/なし両対応 (PowerShell 5.1 の UTF8 with BOM 対策)
            return json.loads(CONFIG_FILE.read_text(encoding="utf-8-sig"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return {}
    return {}


def save_config(cfg: dict) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(
        json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def get_api_key() -> str:
    key = os.environ.get("ANTHROPIC_API_KEY") or load_config().get("apiKey", "")
    if not key:
        _die("ANTHROPIC_API_KEY が未設定です。Setup-ManagedAgents.ps1 を実行してください。")
    return key


def get_client():
    import anthropic
    return anthropic.Anthropic(api_key=get_api_key())


def _die(msg: str) -> None:
    print(json.dumps({"error": msg}, ensure_ascii=False), file=sys.stderr)
    sys.exit(1)


def _out(data: Any) -> None:
    print(json.dumps(data, indent=2, ensure_ascii=False))


# ── Frontmatter パーサー ───────────────────────────────────────────────────────

def parse_frontmatter(text: str) -> tuple[dict, str]:
    """YAML frontmatter を解析して (meta, body) を返す。"""
    if not text.lstrip().startswith("---"):
        return {}, text
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}, text
    meta: dict = {}
    for line in parts[1].strip().splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()
    return meta, parts[2].strip()


def slugify(text: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_-]", "_", text)[:60]


# ── サブコマンド実装 ──────────────────────────────────────────────────────────

def cmd_status(args: argparse.Namespace) -> None:
    cfg = load_config()
    api_key = os.environ.get("ANTHROPIC_API_KEY") or cfg.get("apiKey", "")

    status: dict = {
        "api_key_set": bool(api_key),
        "api_key_prefix": (api_key[:18] + "***") if api_key else None,
        "store_id": cfg.get("memoryStoreId"),
        "config_file": str(CONFIG_FILE),
        "config_exists": CONFIG_FILE.exists(),
        "local_memory_dir": str(MEMORY_DIR),
        "local_memory_dir_exists": MEMORY_DIR.exists(),
        "local_memory_files": (
            len(list(MEMORY_DIR.glob("*.md"))) if MEMORY_DIR.exists() else 0
        ),
    }

    if api_key and cfg.get("memoryStoreId"):
        try:
            client = get_client()
            store = client.beta.memory_stores.retrieve(cfg["memoryStoreId"])
            mems = list(client.beta.memory_stores.memories.list(cfg["memoryStoreId"]))
            status["store_status"] = "ok"
            status["store_name"] = store.name
            status["remote_memory_count"] = len(mems)
        except Exception as e:
            status["store_status"] = f"error: {e}"

    _out(status)


def cmd_create_store(args: argparse.Namespace) -> None:
    client = get_client()
    name = args.name or STORE_NAME
    desc = args.description or STORE_DESC

    store = client.beta.memory_stores.create(name=name, description=desc)
    cfg = load_config()
    cfg["memoryStoreId"] = store.id
    save_config(cfg)

    _out({
        "success": True,
        "store_id": store.id,
        "name": store.name,
        "description": store.description,
        "message": f"store_id を {CONFIG_FILE} に保存しました。",
    })


def cmd_migrate(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()
    store_id: str = args.store_id or cfg.get("memoryStoreId") or ""
    if not store_id:
        _die("--store-id か config の memoryStoreId が必要です。")

    mem_dir = Path(args.memory_dir) if args.memory_dir else MEMORY_DIR
    if not mem_dir.exists():
        _die(f"memory ディレクトリが見つかりません: {mem_dir}")

    md_files = [f for f in mem_dir.glob("*.md") if f.name != "MEMORY.md"]
    results = []

    for md_file in md_files:
        content = md_file.read_text(encoding="utf-8")
        fm, _ = parse_frontmatter(content)
        mem_type = fm.get("type", "general")
        path = f"/{mem_type}/{md_file.stem}.md"

        try:
            mem = client.beta.memory_stores.memories.create(
                store_id, path=path, content=content
            )
            results.append({
                "file": md_file.name,
                "path": path,
                "id": mem.id,
                "status": "created",
            })
        except Exception as e:
            err_str = str(e).lower()
            if "already exist" in err_str or "conflict" in err_str or "409" in err_str:
                results.append({"file": md_file.name, "path": path, "status": "skipped_exists"})
            else:
                results.append({"file": md_file.name, "path": path, "status": "error", "error": str(e)})

    created = sum(1 for r in results if r["status"] == "created")
    _out({
        "success": True,
        "store_id": store_id,
        "total": len(results),
        "created": created,
        "skipped": len(results) - created,
        "results": results,
    })


def cmd_list(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()
    store_id: str = args.store_id or cfg.get("memoryStoreId") or ""
    if not store_id:
        _die("--store-id か config の memoryStoreId が必要です。")

    mems = []
    for mem in client.beta.memory_stores.memories.list(
        store_id, path_prefix="/", order_by="path", depth=4
    ):
        mems.append({
            "id": mem.id,
            "path": mem.path,
            "type": getattr(mem, "type", "memory"),
        })

    _out({"store_id": store_id, "count": len(mems), "memories": mems})


def cmd_read(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()
    store_id: str = args.store_id or cfg.get("memoryStoreId") or ""
    if not store_id:
        _die("--store-id か config の memoryStoreId が必要です。")

    for mem in client.beta.memory_stores.memories.list(
        store_id, path_prefix=args.path
    ):
        if mem.path == args.path:
            retrieved = client.beta.memory_stores.memories.retrieve(
                mem.id, memory_store_id=store_id
            )
            _out({
                "id": retrieved.id,
                "path": retrieved.path,
                "content": retrieved.content,
                "content_sha256": retrieved.content_sha256,
            })
            return

    _die(f"メモリが見つかりません: {args.path}")


def cmd_write(args: argparse.Namespace) -> None:
    client = get_client()
    cfg = load_config()
    store_id: str = args.store_id or cfg.get("memoryStoreId") or ""
    if not store_id:
        _die("--store-id か config の memoryStoreId が必要です。")

    content = args.content if args.content != "-" else sys.stdin.read()

    # 既存チェック
    existing = None
    for mem in client.beta.memory_stores.memories.list(
        store_id, path_prefix=args.path
    ):
        if mem.path == args.path:
            existing = mem
            break

    if existing:
        retrieved = client.beta.memory_stores.memories.retrieve(
            existing.id, memory_store_id=store_id
        )
        updated = client.beta.memory_stores.memories.update(
            existing.id,
            memory_store_id=store_id,
            content=content,
            precondition={
                "type": "content_sha256",
                "content_sha256": retrieved.content_sha256,
            },
        )
        _out({"action": "updated", "id": updated.id, "path": updated.path})
    else:
        mem = client.beta.memory_stores.memories.create(
            store_id, path=args.path, content=content
        )
        _out({"action": "created", "id": mem.id, "path": mem.path})


def cmd_sync(args: argparse.Namespace) -> None:
    """ローカル .md ファイルとリモート Memory Store を同期する。"""
    client = get_client()
    cfg = load_config()
    store_id: str = args.store_id or cfg.get("memoryStoreId") or ""
    if not store_id:
        _die("--store-id か config の memoryStoreId が必要です。")

    mem_dir = Path(args.memory_dir) if args.memory_dir else MEMORY_DIR
    direction = args.direction or "push"

    if direction == "push":
        # ローカル → リモート（create-store 後の継続同期）
        fake_args = argparse.Namespace(
            store_id=store_id, memory_dir=str(mem_dir)
        )
        cmd_migrate(fake_args)

    elif direction == "pull":
        # リモート → ローカル（別端末からの取得）
        if not mem_dir.exists():
            mem_dir.mkdir(parents=True, exist_ok=True)

        pulled = []
        for mem in client.beta.memory_stores.memories.list(
            store_id, path_prefix="/", order_by="path"
        ):
            retrieved = client.beta.memory_stores.memories.retrieve(
                mem.id, memory_store_id=store_id
            )
            filename = Path(mem.path).name
            out_path = mem_dir / filename
            out_path.write_text(retrieved.content or "", encoding="utf-8")
            pulled.append({"path": mem.path, "file": str(out_path)})

        _out({"direction": "pull", "pulled": pulled, "count": len(pulled)})

    else:
        _die(f"不明な direction: {direction}  (push | pull のどちらか)")


# ── CLI エントリーポイント ────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Managed Agents Memory Store CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("status", help="設定とストア状態を確認")

    p = sub.add_parser("create-store", help="Memory Store を新規作成")
    p.add_argument("--name", default="")
    p.add_argument("--description", default="")

    p = sub.add_parser("migrate", help="ローカル .md ファイルをストアへ移行")
    p.add_argument("--store-id", default="")
    p.add_argument("--memory-dir", default="")

    p = sub.add_parser("list", help="ストア内のメモリ一覧")
    p.add_argument("--store-id", default="")

    p = sub.add_parser("read", help="メモリを読み取る")
    p.add_argument("--store-id", default="")
    p.add_argument("--path", required=True, help="例: /feedback/foo.md")

    p = sub.add_parser("write", help="メモリを書き込む / 更新する")
    p.add_argument("--store-id", default="")
    p.add_argument("--path", required=True, help="例: /feedback/foo.md")
    p.add_argument("--content", default="-", help="テキスト or - (stdin)")

    p = sub.add_parser("sync", help="ローカル <-> リモートを同期")
    p.add_argument("--store-id", default="")
    p.add_argument("--memory-dir", default="")
    p.add_argument("--direction", choices=["push", "pull"], default="push")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    dispatch = {
        "status": cmd_status,
        "create-store": cmd_create_store,
        "migrate": cmd_migrate,
        "list": cmd_list,
        "read": cmd_read,
        "write": cmd_write,
        "sync": cmd_sync,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
