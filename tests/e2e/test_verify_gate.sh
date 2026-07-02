#!/bin/sh
# E2E: claude/hooks/verify-gate-pretooluse.sh (+ verify-gate-check.py)
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/claude/hooks/verify-gate-pretooluse.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-verify-gate-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP"
export VERIFY_GATE_LOG="$TMP/gate.log"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Feed a hook JSON whose tool_input.command is $1; assert exit code $2.
# Extra env (e.g. VERIFY_GATE=off) can be prefixed by the caller.
run_cmd() {  # $1=command $2=expected_exit [$3=label]
  _cmd="$1"; _want="$2"; _label="${3:-$1}"
  _json=$(CMD="$_cmd" python3 -c 'import json,os;print(json.dumps({"tool_input":{"command":os.environ["CMD"]}}))')
  set +e
  printf '%s' "$_json" | bash "$HOOK" >/dev/null 2>&1
  _got=$?
  set -e
  [ "$_got" -eq "$_want" ] || fail "[$_label] expected exit $_want, got $_got"
}

GOOD_BODY='## Summary
Fix the thing.
## Verification
Ran unit tests + e2e; all green. Tested manually in staging.
## Grading
Independent review subagent checked the diff and evidence; 1 finding fixed.'

NO_GRADE_BODY='## Verification
Ran the tests, e2e passed.'

NO_VERIFY_BODY='## Grading
Independent reviewer subagent looked at the diff.'

DOCS_BODY='## Summary
Typo fix.
## Verification
Docs only, no runtime.
## Grading
Independent review subagent confirmed docs-only, no code path affected.'

# --- non-PR bash passes untouched ---
run_cmd 'ls -la' 0 'plain ls'
run_cmd 'git status && echo done' 0 'compound non-pr'

# --- gh pr create WITH both sections → allow ---
run_cmd "gh pr create --title t --body '$GOOD_BODY'" 0 'full body inline'

# --- missing grading → block ---
run_cmd "gh pr create --title t --body '$NO_GRADE_BODY'" 2 'missing grading'

# --- missing verification → block ---
run_cmd "gh pr create --title t --body '$NO_VERIFY_BODY'" 2 'missing verification'

# --- no body at all → block ---
run_cmd 'gh pr create --title t' 2 'no body'

# --- docs-only body satisfies (scaled bar) → allow ---
run_cmd "gh pr create --body '$DOCS_BODY'" 0 'docs-only body'

# --- kill switch: bad body but VERIFY_GATE=off → allow ---
_json=$(CMD="gh pr create --title t" python3 -c 'import json,os;print(json.dumps({"tool_input":{"command":os.environ["CMD"]}}))')
set +e
printf '%s' "$_json" | VERIFY_GATE=off bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] || fail "[kill switch] expected exit 0"
set -e

# --- malformed hook JSON → fail open (allow) ---
set +e
printf '%s' '{ not json' | bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] || fail "[malformed json] expected fail-open exit 0"
set -e

# --- --body-file with both sections → allow ---
printf '%s' "$GOOD_BODY" >"$TMP/body.md"
run_cmd "gh pr create --title t --body-file $TMP/body.md" 0 'body-file allow'

# --- --body-file missing grading → block ---
printf '%s' "$NO_GRADE_BODY" >"$TMP/body2.md"
run_cmd "gh pr create --title t --body-file $TMP/body2.md" 2 'body-file missing grading'

# --- --fill (un-inspectable) → fail open (allow), don't false-block ---
run_cmd 'gh pr create --fill' 0 'fill allow'

# --- --body-file that doesn't exist → fail open (can't inspect) → allow ---
run_cmd "gh pr create --title t --body-file $TMP/does-not-exist.md" 0 'unreadable body-file allow'

echo "verify-gate: all cases passed"
exit 0
