#!/usr/bin/env python3
"""
Merge user MCP servers from Claude Code (~/.claude.json mcpServers) into Cursor mcp.json.

Strips Claude-only fields (e.g. type). Only adds/updates entries present in Claude;
does not remove Cursor-only servers.
"""

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Optional


def to_cursor_entry(cfg: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(cfg, dict):
        return None
    out = {k: v for k, v in cfg.items() if k != "type"}
    if out.get("env") == {}:
        out.pop("env", None)
    return out


def sync(claude_path: str, cursor_path: str) -> int:
    if not os.path.isfile(claude_path):
        return 0

    try:
        with open(claude_path, encoding="utf-8") as f:
            claude = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(
            f"⚠️  Claude → Cursor MCP sync: could not read {claude_path}: {e}",
            file=sys.stderr,
        )
        return 1

    raw = claude.get("mcpServers")
    if not isinstance(raw, dict) or not raw:
        return 0

    converted: Dict[str, Dict[str, Any]] = {}
    for name, cfg in raw.items():
        entry = to_cursor_entry(cfg)
        if entry:
            converted[name] = entry

    if not converted:
        return 0

    os.makedirs(os.path.dirname(cursor_path) or ".", exist_ok=True)
    data: Dict[str, Any] = {}
    if os.path.isfile(cursor_path):
        with open(cursor_path, encoding="utf-8") as f:
            data = json.load(f)

    ms = data.setdefault("mcpServers", {})
    changed: List[str] = []
    for name, cfg in converted.items():
        if ms.get(name) != cfg:
            ms[name] = cfg
            changed.append(name)

    if changed:
        with open(cursor_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print("✅ Cursor MCP: synced from Claude Code:", ", ".join(changed))
    else:
        n = len(converted)
        plural = "s" if n != 1 else ""
        print(f"✅ Cursor MCP: Claude sync OK ({n} server{plural}, no changes needed)")

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--claude-json",
        default=os.path.expanduser("~/.claude.json"),
        help="Path to Claude Code user config (default: ~/.claude.json)",
    )
    parser.add_argument(
        "--cursor-mcp",
        default=os.path.expanduser("~/.cursor/mcp.json"),
        help="Path to Cursor MCP config (default: ~/.cursor/mcp.json)",
    )
    args = parser.parse_args()
    return sync(args.claude_json, args.cursor_mcp)


if __name__ == "__main__":
    raise SystemExit(main())
