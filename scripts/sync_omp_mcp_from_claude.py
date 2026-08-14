#!/usr/bin/env python3
"""Sync Claude Code's Glean MCP server into an omp-local mcp.json overlay.

omp's mcp.json format is close to Claude's native mcpServers block (stdio uses
command/args/env; remote uses type:http + url + headers), and omp expands ${VAR}
at load, so this mostly copies the wanted servers through while redacting inlined
secrets back to ${VAR} references. Mirrors sync_opencode_mcp_from_claude.py.
"""

import argparse
import json
import os
import re
import shutil
import sys

OMP_MCP_SERVERS = {"glean_default"}


def redact(value, environment):
    """Replace inlined secret values with ${NAME} and keep existing ${VAR} refs."""
    matches = sorted(
        (
            (name, env_value)
            for name, env_value in environment.items()
            if len(env_value) >= 8 and env_value in value
        ),
        key=lambda item: (-len(item[1]), item[0]),
    )

    def replace_literal(literal):
        for name, env_value in matches:
            literal = literal.replace(env_value, f"${{{name}}}")
        return literal

    output = []
    position = 0
    pattern = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")
    for match in pattern.finditer(value):
        output.append(replace_literal(value[position : match.start()]))
        name, _fallback = match.groups()
        output.append(f"${{{name}}}")
        position = match.end()
    output.append(replace_literal(value[position:]))
    return "".join(output)


def to_omp_entry(config, environment):
    if not isinstance(config, dict):
        return None
    if config.get("headersHelper") is not None:
        return None

    server_type = config.get("type")
    if server_type not in (None, "stdio", "http", "sse", "streamable-http"):
        return None

    if server_type in ("http", "sse", "streamable-http") or (
        server_type is None and isinstance(config.get("url"), str)
    ):
        url = config.get("url")
        if not isinstance(url, str):
            return None
        entry = {"type": "http", "url": redact(url, environment)}
        if isinstance(config.get("headers"), dict):
            entry["headers"] = {
                name: redact(value, environment)
                for name, value in config["headers"].items()
                if isinstance(value, str)
            }
        return entry

    command = config.get("command")
    args = config.get("args", [])
    if not isinstance(command, str) or not isinstance(args, list):
        return None
    if not all(isinstance(arg, str) for arg in args):
        return None

    entry = {"command": redact(command, environment)}
    if args:
        entry["args"] = [redact(arg, environment) for arg in args]
    if isinstance(config.get("env"), dict) and config["env"]:
        entry["env"] = {
            name: redact(value, environment)
            for name, value in config["env"].items()
            if isinstance(value, str)
        }
    return entry


def back_up_existing_overlay(path):
    backup = f"{path}.pre-authoritative-sync"
    try:
        descriptor = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return
    try:
        with os.fdopen(descriptor, "wb") as target, open(path, "rb") as source:
            shutil.copyfileobj(source, target)
    except Exception:
        os.unlink(backup)
        raise


def sync(claude_path, omp_path):
    if os.path.isfile(omp_path):
        try:
            os.chmod(omp_path, 0o600)
        except OSError as error:
            print(f"Claude -> omp MCP sync: could not secure {omp_path}: {error}", file=sys.stderr)
            return 1

    if not os.path.isfile(claude_path):
        return 0

    try:
        with open(claude_path, encoding="utf-8") as file:
            claude = json.load(file)
    except (OSError, json.JSONDecodeError) as error:
        print(f"Claude -> omp MCP sync: could not read {claude_path}: {error}", file=sys.stderr)
        return 1

    raw = claude.get("mcpServers", {})
    if not isinstance(raw, dict):
        return 0

    converted = {}
    skipped = []
    for name, config in raw.items():
        if name not in OMP_MCP_SERVERS:
            continue
        entry = to_omp_entry(config, os.environ)
        if entry:
            converted[name] = entry
        else:
            skipped.append(name)
    if skipped:
        print("Claude -> omp MCP sync: skipped unsupported servers: " + ", ".join(skipped), file=sys.stderr)

    os.makedirs(os.path.dirname(omp_path) or ".", exist_ok=True)
    data = {"mcpServers": converted}
    existing = None
    if os.path.isfile(omp_path) and os.path.getsize(omp_path) > 0:
        try:
            with open(omp_path, encoding="utf-8") as file:
                existing = json.load(file)
        except (OSError, json.JSONDecodeError) as error:
            print(f"Claude -> omp MCP sync: could not read {omp_path}: {error}", file=sys.stderr)
            return 1

    if existing != data:
        if existing is not None:
            back_up_existing_overlay(omp_path)
        temporary = f"{omp_path}.tmp"
        with open(temporary, "w", encoding="utf-8") as file:
            json.dump(data, file, indent=2)
            file.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, omp_path)
        print(f"omp MCP: synced from Claude Code ({len(converted)} servers)")
    else:
        count = len(converted)
        suffix = "s" if count != 1 else ""
        print(f"omp MCP: Claude sync OK ({count} server{suffix}, no changes needed)")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--claude-json",
        default=os.path.expanduser("~/.claude.json"),
        help="Path to Claude Code user config (default: ~/.claude.json)",
    )
    parser.add_argument(
        "--omp-mcp",
        default=os.path.join(
            os.environ.get("PI_CODING_AGENT_DIR", os.path.expanduser("~/.omp/agent")),
            "mcp.json",
        ),
        help="Path to omp MCP overlay (default: ~/.omp/agent/mcp.json)",
    )
    arguments = parser.parse_args()
    return sync(arguments.claude_json, arguments.omp_mcp)


if __name__ == "__main__":
    raise SystemExit(main())
