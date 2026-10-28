#!/usr/bin/env python3
"""Apply host-local Codex defaults without replacing unrelated configuration."""

import json
import os
from pathlib import Path
import sys
import tomllib


DEFAULTS = {
    "model": "gpt-6.1-sol",
    "model_reasoning_effort": "high",
    "approval_policy": "on-request",
    "approvals_reviewer": "auto_review",
    "sandbox_mode": "workspace-write",
}


def configure(path):
    original = path.read_text() if path.exists() else ""
    parsed = tomllib.loads(original)
    if all(parsed.get(key) == value for key, value in DEFAULTS.items()):
        return

    lines = original.splitlines(keepends=True)
    retained = []
    statement = ""
    for index, line in enumerate(lines):
        statement += line
        try:
            values = tomllib.loads(statement)
        except tomllib.TOMLDecodeError:
            continue
        if statement.lstrip().startswith("["):
            retained.append("".join(lines[index:]))
            break
        if not DEFAULTS.keys() & values.keys():
            retained.append(statement)
        statement = ""

    updated = "".join(f"{key} = {json.dumps(value)}\n" for key, value in DEFAULTS.items())
    updated += "".join(retained)
    expected = dict(parsed, **DEFAULTS)
    if tomllib.loads(updated) != expected:
        raise ValueError("Cannot preserve unrelated Codex configuration")

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", opener=lambda file, flags: os.open(file, flags, 0o600)) as output:
        output.write(updated)


if __name__ == "__main__":
    codex_home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    configure(Path(sys.argv[1]) if len(sys.argv) > 1 else codex_home / "config.toml")
