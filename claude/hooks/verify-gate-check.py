#!/usr/bin/env python3
"""Decide whether a PreToolUse(Bash) call is a `gh pr create` missing evidence.

Reads the hook JSON on stdin. Exit 2 (with a stderr message) blocks the call;
exit 0 allows it. Fails OPEN (exit 0) on anything unexpected - the gate must only
ever block a deliberate, inspectable miss, never wedge on a parse error.
"""
import json
import os
import re
import shlex
import sys


def log(msg):
    path = os.environ.get("VG_LOG")
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except Exception:
        pass


def allow(reason):
    log("allow: " + reason)
    sys.exit(0)


def block(missing):
    log("block: " + "; ".join(missing))
    sys.stderr.write(BLOCK_MSG.format(missing="\n".join("  • " + m for m in missing)))
    sys.exit(2)


BLOCK_MSG = """⛔ Verify gate: this PR isn't ready for a human's eyes yet.

Missing from the PR body:
{missing}

Before `gh pr create`, run the verification + independent-review workflow
(~/dotfiles/shared-skills/full-verification-workflow) and put the results in the body:
  - a Verification/Evidence section (commands run + results; e2e/browser/manual when the
    change warrants it), and
  - a Grading section from an INDEPENDENT review - dispatch a clean-context review subagent
    over the diff + evidence, then record its verdict + findings-fixed.

The evidence bar scales to the change: a docs-only PR just needs "docs only, no runtime".
Kill switch (escape hatch): export VERIFY_GATE=off
"""

# Lenient on purpose: match the *presence* of a section, not an exact heading, so the
# gate is low-false-positive across repos. A docs PR satisfies VERIFICATION with a line
# like "docs only, no runtime".
VERIFICATION = re.compile(
    r"(?i)(##\s*(verification|test|testing|evidence|qa)\b"
    r"|verification evidence|test plan|\btested\b|verified (that|by|it|with)"
    r"|\be2e\b|end[- ]to[- ]end|manual (test|verification)|screenshot"
    r"|\btypecheck\b|\bunit tests?\b|verification commands"
    r"|docs?[ -]only|no runtime|no code change)"
)
GRADING = re.compile(
    r"(?i)(independent (review|grade|grader|grading|pass)"
    r"|##\s*grading|grading notes|\breviewer\b|review (agent|subagent|pass)"
    r"|graded by|second[- ]pass review|adversarial review"
    r"|reviewed by (a |an )?(sub)?agent)"
)


def is_gh_pr_create(tokens):
    for i in range(len(tokens) - 2):
        t = tokens[i]
        if (t == "gh" or t.endswith("/gh")) and tokens[i + 1] == "pr" and tokens[i + 2] == "create":
            return True
    return False


def extract_body(tokens):
    """Return (body_text, note). body_text is None when it can't be determined."""
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t in ("--body", "-b") and i + 1 < len(tokens):
            return tokens[i + 1], "inline"
        if t.startswith("--body="):
            return t[len("--body="):], "inline"
        if t in ("--body-file", "-F") and i + 1 < len(tokens):
            return read_file(tokens[i + 1]), "file"
        if t.startswith("--body-file="):
            return read_file(t[len("--body-file="):]), "file"
        # --fill / --fill-first / --fillverbose: body derived from commits - not inspectable.
        if t.startswith("--fill"):
            return None, "fill"
        i += 1
    return None, "none"


def read_file(path):
    try:
        with open(os.path.expanduser(path), encoding="utf-8") as f:
            return f.read()
    except Exception:
        return None


def main():
    raw = sys.stdin.read()
    data = json.loads(raw)  # any failure → outer except → allow
    cmd = data.get("tool_input", {}).get("command", "")
    if not isinstance(cmd, str) or not cmd.strip():
        allow("no command string")

    tokens = shlex.split(cmd)  # may raise on unbalanced quotes → allow
    if not is_gh_pr_create(tokens):
        allow("not gh pr create")

    body, note = extract_body(tokens)

    if note == "fill":
        # Legitimate but un-inspectable; don't false-block. Primed behavior won't use --fill.
        allow("--fill body not inspectable")
    if body is None and note == "file":
        allow("--body-file unreadable - can't inspect, so can't fairly block")
    if body is None:
        block([
            "no PR body found (use --body / --body-file) - so no verification evidence",
            "an independent-review/grading section",
        ])

    missing = []
    if not VERIFICATION.search(body):
        missing.append("a Verification/Evidence section (what you ran + results)")
    if not GRADING.search(body):
        missing.append("a Grading section from an independent review subagent")
    if missing:
        block(missing)
    allow("evidence + grading present")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # fail open on anything unexpected
        log("fail-open: " + repr(e))
        sys.exit(0)
