#!/usr/bin/env bash
# Idempotently register the scope-gate hooks into a Claude settings.json.
# Non-clobbering: preserves existing hooks (e.g. the RTK Bash PreToolUse entry).
# Usage: scope-gate-register.sh [path-to-settings.json]   (default: ~/.claude/settings.json)
set -uo pipefail
CFG="${1:-$HOME/.claude/settings.json}"
command -v python3 >/dev/null 2>&1 || { echo "scope-gate-register: python3 required" >&2; exit 1; }

python3 - "$CFG" <<'PY'
import json, os, sys
path = os.path.expanduser(sys.argv[1])
home = os.path.expanduser("~")
pre_cmd = f"{home}/dotfiles/scripts/scope-gate-pretooluse.sh"
ups_cmd = f"{home}/dotfiles/scripts/scope-gate-userpromptsubmit.sh"

os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})

def has_cmd(arr, cmd):
    return any(h.get("command") == cmd for entry in arr for h in entry.get("hooks", []))

pre = hooks.setdefault("PreToolUse", [])
if not has_cmd(pre, pre_cmd):
    pre.append({"matcher": "Edit|Write", "hooks": [{"type": "command", "command": pre_cmd}]})

ups = hooks.setdefault("UserPromptSubmit", [])
if not has_cmd(ups, ups_cmd):
    ups.append({"hooks": [{"type": "command", "command": ups_cmd}]})

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
