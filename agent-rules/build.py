#!/usr/bin/env python3
"""Compile tool-agnostic agent rules into each tool's native format.

`agent-rules/` is the single source of truth for rules that several agent tools
share. Each rule has a tool-agnostic body (`<name>.md`) plus per-tool settings in
`rules.json`. This script renders the tool-specific files (today: Cursor `.mdc`
into both `cursor/rules/` and `cursor/rules-work/` per each rule's scope).

Generated files are committed so the tools work without a build step; `--check`
re-renders in memory and fails if any committed file drifts from its source, so
the copies can't silently diverge. Adding a tool means adding an emitter here;
adding a rule means adding a source file and a `rules.json` entry.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent
MANIFEST = ROOT / "rules.json"

CURSOR_DIRS = {
    "personal": REPO / "cursor" / "rules",
    "work": REPO / "cursor" / "rules-work",
}


def render_cursor(settings, body):
    lines = ["---", f"description: {settings['description']}"]
    if "globs" in settings:
        lines.append(f"globs: {settings['globs']}")
    lines.append(f"alwaysApply: {'true' if settings.get('alwaysApply', False) else 'false'}")
    lines.append("---")
    return "\n".join(lines) + "\n\n" + body


def cursor_dests(scope):
    if scope == "both":
        return [CURSOR_DIRS["personal"], CURSOR_DIRS["work"]]
    if scope in CURSOR_DIRS:
        return [CURSOR_DIRS[scope]]
    raise ValueError(f"unknown cursor scope: {scope!r} (expected both|personal|work)")


def outputs(manifest):
    """Yield (path, content) for every file the manifest says to generate."""
    for name, rule in manifest.items():
        body = (ROOT / rule["body"]).read_text()
        for target, settings in rule["targets"].items():
            if target != "cursor":
                raise ValueError(f"{name}: unsupported target {target!r} (only 'cursor' so far)")
            content = render_cursor(settings, body)
            for dest_dir in cursor_dests(settings.get("scope", "both")):
                yield dest_dir / settings["file"], content


def main():
    check = "--check" in sys.argv
    manifest = json.loads(MANIFEST.read_text())
    planned = list(outputs(manifest))

    if check:
        drift = [p for p, c in planned if (not p.exists()) or p.read_text() != c]
        if drift:
            sys.stderr.write("agent-rules: generated files are stale — run `python3 agent-rules/build.py`:\n")
            for p in drift:
                sys.stderr.write(f"  - {p.relative_to(REPO)}\n")
            return 1
        print(f"agent-rules: {len(planned)} generated file(s) up to date")
        return 0

    for path, content in planned:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    print(f"agent-rules: wrote {len(planned)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
