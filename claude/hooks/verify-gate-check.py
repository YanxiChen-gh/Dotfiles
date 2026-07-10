#!/usr/bin/env python3
"""Decide whether a PreToolUse(Bash) call is a `gh pr create` missing evidence.

Reads the hook JSON on stdin. Exit 2 (with a stderr message) blocks the call;
exit 0 allows it. Fails OPEN (exit 0) on anything unexpected - the gate must only
ever block a deliberate, inspectable miss, never wedge on a parse error.

Work-scoped: the verification ceremony is the Vanta PR handoff, so the gate
only fires on work-org repos. Personal repos (push-to-main once verified) are skipped.
"""
import json
import os
import re
import shlex
import subprocess
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
(~/dotfiles/shared-skills/full-verification-workflow), then put reviewer-useful verification
in the body (e2e/browser/manual when the change warrants it). Keep routine CI results and
independent grading notes out of the PR description.

The evidence bar scales to the change: a docs-only PR just needs "docs only, no runtime".
Kill switch (escape hatch): export VERIFY_GATE=off
"""

# Require evidence beyond checks CI already carries, inside the repository's evidence section.
VERIFICATION_SECTION = re.compile(
    r"(?ims)^##\s*(?:verification|tests?|testing|evidence|qa)\b(?P<body>.*?)(?=^##\s|\Z)"
)
REVIEWER_USEFUL = re.compile(
    r"(?i)(\be2e\b|end[- ]to[- ]end|manual(?:ly| test| verification)?"
    r"|browser|screenshot|reproduc(?:e|ed|ible)|failure[- ]path|round[- ]trip"
    r"|authenticated|queried|returned (?:http )?\d{3}"
    r"|tested (?:in|against|with)|verified (?:in|against|with|by|that))"
)
DOCS_ONLY = re.compile(r"(?i)(docs?[ -]only|no runtime|no code change)")


def has_reviewer_useful_verification(body):
    return any(
        REVIEWER_USEFUL.search(match.group("body")) or DOCS_ONLY.search(match.group("body"))
        for match in VERIFICATION_SECTION.finditer(body)
    )
# The gate is the Vanta PR handoff ceremony, so it only fires on work-org repos.
# Default org is Vanta; override with a comma-separated VERIFY_GATE_WORK_ORGS.
def work_orgs():
    return [o.strip() for o in os.environ.get("VERIFY_GATE_WORK_ORGS", "VantaInc").split(",") if o.strip()]


def _org_matches(text, orgs):
    return any(re.search(r"github\.com[:/]" + re.escape(o) + r"/", text, re.I) for o in orgs)


def is_work_repo(tokens, cwd):
    """True when the PR targets a work-org repo. Any uncertainty → False (skip the gate)."""
    orgs = work_orgs()
    if not orgs:
        return False

    # An explicit `gh -R <owner>/<repo>` (or a `--repo` URL) overrides cwd, so honor it first.
    repo_flag = extract_repo_flag(tokens)
    if repo_flag is not None:
        owner = repo_flag.split("/")[0]
        return owner.lower() in {o.lower() for o in orgs} or _org_matches(repo_flag, orgs)

    try:
        proc = subprocess.run(
            ["git", "-C", cwd or ".", "remote", "-v"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return False
    if proc.returncode != 0:
        return False
    return _org_matches(proc.stdout, orgs)


def extract_repo_flag(tokens):
    """Return the value of gh's `-R`/`--repo` flag, or None."""
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t in ("-R", "--repo") and i + 1 < len(tokens):
            return tokens[i + 1]
        if t.startswith("--repo="):
            return t[len("--repo="):]
        i += 1
    return None


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

    if not is_work_repo(tokens, data.get("cwd") or os.getcwd()):
        allow("non-work repo - verify gate is work-scoped")

    body, note = extract_body(tokens)

    if note == "fill":
        # Legitimate but un-inspectable; don't false-block. Primed behavior won't use --fill.
        allow("--fill body not inspectable")
    if body is None and note == "file":
        allow("--body-file unreadable - can't inspect, so can't fairly block")
    if body is None:
        block([
            "no PR body found (use --body / --body-file) - so no verification evidence",
        ])

    missing = []
    if not has_reviewer_useful_verification(body):
        missing.append("reviewer-useful verification beyond routine CI checks")
    if missing:
        block(missing)
    allow("verification evidence present")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # fail open on anything unexpected
        log("fail-open: " + repr(e))
        sys.exit(0)
