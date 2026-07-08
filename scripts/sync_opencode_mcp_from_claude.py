#!/usr/bin/env python3
"""Merge Claude Code user MCP servers into an OpenCode-local config overlay."""

import argparse
import json
import os
import re
import sys


def replace_environment_values(value, environment):
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
            literal = literal.replace(env_value, f"{{env:{name}}}")
        return literal

    output = []
    position = 0
    pattern = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")
    for match in pattern.finditer(value):
        output.append(replace_literal(value[position : match.start()]))
        name, fallback = match.groups()
        output.append(f"{{env:{name}}}" if fallback is None else f"{{env:{name}:-{fallback}}}")
        position = match.end()
    output.append(replace_literal(value[position:]))
    return "".join(output)


def to_opencode_entry(config, environment):
    if not isinstance(config, dict):
        return None

    server_type = config.get("type")
    if config.get("headersHelper") is not None:
        return None
    if server_type not in (None, "stdio", "http", "sse", "streamable-http"):
        return None

    if server_type in ("http", "sse", "streamable-http") or (
        server_type is None and isinstance(config.get("url"), str)
    ):
        url = config.get("url")
        if not isinstance(url, str):
            return None
        entry = {
            "type": "remote",
            "url": replace_environment_values(url, environment),
            "enabled": True,
        }
        if isinstance(config.get("headers"), dict):
            entry["headers"] = {
                name: replace_environment_values(value, environment)
                for name, value in config["headers"].items()
                if isinstance(value, str)
            }
        oauth = config.get("oauth")
        if oauth is False:
            entry["oauth"] = False
        elif isinstance(oauth, dict):
            converted_oauth = {}
            for name in ("clientId", "clientSecret", "scope", "redirectUri"):
                value = oauth.get(name)
                if isinstance(value, str):
                    converted_oauth[name] = replace_environment_values(value, environment)
            scopes = oauth.get("scopes")
            if "scope" not in converted_oauth:
                if isinstance(scopes, str):
                    converted_oauth["scope"] = scopes
                elif isinstance(scopes, list) and all(
                    isinstance(scope, str) for scope in scopes
                ):
                    converted_oauth["scope"] = " ".join(scopes)
            callback_port = oauth.get("callbackPort")
            if (
                isinstance(callback_port, int)
                and not isinstance(callback_port, bool)
                and 1 <= callback_port <= 65535
            ):
                converted_oauth["callbackPort"] = callback_port
            entry["oauth"] = converted_oauth
        timeout = config.get("timeout")
        if isinstance(timeout, int) and not isinstance(timeout, bool) and timeout > 0:
            entry["timeout"] = timeout
        return entry

    command = config.get("command")
    args = config.get("args", [])
    if not isinstance(command, str) or not isinstance(args, list):
        return None
    if not all(isinstance(arg, str) for arg in args):
        return None

    entry = {
        "type": "local",
        "command": [
            replace_environment_values(value, environment) for value in [command, *args]
        ],
        "enabled": True,
    }
    if isinstance(config.get("env"), dict) and config["env"]:
        entry["environment"] = {
            name: replace_environment_values(value, environment)
            for name, value in config["env"].items()
            if isinstance(value, str)
        }
    cwd = config.get("cwd")
    if isinstance(cwd, str):
        entry["cwd"] = cwd
    timeout = config.get("timeout")
    if isinstance(timeout, int) and not isinstance(timeout, bool) and timeout > 0:
        entry["timeout"] = timeout
    return entry


def sync(claude_path, opencode_path):
    if os.path.isfile(opencode_path):
        try:
            os.chmod(opencode_path, 0o600)
        except OSError as error:
            print(
                f"Claude -> OpenCode MCP sync: could not secure {opencode_path}: {error}",
                file=sys.stderr,
            )
            return 1

    if not os.path.isfile(claude_path):
        return 0

    try:
        with open(claude_path, encoding="utf-8") as file:
            claude = json.load(file)
    except (OSError, json.JSONDecodeError) as error:
        print(
            f"Claude -> OpenCode MCP sync: could not read {claude_path}: {error}",
            file=sys.stderr,
        )
        return 1

    raw = claude.get("mcpServers")
    if not isinstance(raw, dict) or not raw:
        return 0

    converted = {}
    skipped = []
    for name, config in raw.items():
        entry = to_opencode_entry(config, os.environ)
        if entry:
            converted[name] = entry
        else:
            skipped.append(name)
    if skipped:
        print(
            "Claude -> OpenCode MCP sync: skipped unsupported servers: "
            + ", ".join(skipped),
            file=sys.stderr,
        )
    if not converted:
        return 0

    os.makedirs(os.path.dirname(opencode_path) or ".", exist_ok=True)
    data = {"mcp": {}}
    if os.path.isfile(opencode_path) and os.path.getsize(opencode_path) > 0:
        try:
            with open(opencode_path, encoding="utf-8") as file:
                data = json.load(file)
        except (OSError, json.JSONDecodeError) as error:
            print(
                f"Claude -> OpenCode MCP sync: could not read {opencode_path}: {error}",
                file=sys.stderr,
            )
            return 1

    servers = data.setdefault("mcp", {})
    changed = []
    for name, config in converted.items():
        if servers.get(name) != config:
            servers[name] = config
            changed.append(name)

    if changed:
        temporary = f"{opencode_path}.tmp"
        with open(temporary, "w", encoding="utf-8") as file:
            json.dump(data, file, indent=2)
            file.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, opencode_path)
        print("OpenCode MCP: synced from Claude Code:", ", ".join(changed))
    else:
        count = len(converted)
        suffix = "s" if count != 1 else ""
        print(f"OpenCode MCP: Claude sync OK ({count} server{suffix}, no changes needed)")

    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--claude-json",
        default=os.path.expanduser("~/.claude.json"),
        help="Path to Claude Code user config (default: ~/.claude.json)",
    )
    parser.add_argument(
        "--opencode-mcp",
        default=os.path.join(
            os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
            "opencode/mcp.json",
        ),
        help="Path to OpenCode MCP overlay (default: $XDG_CONFIG_HOME/opencode/mcp.json)",
    )
    arguments = parser.parse_args()
    return sync(arguments.claude_json, arguments.opencode_mcp)


if __name__ == "__main__":
    raise SystemExit(main())
