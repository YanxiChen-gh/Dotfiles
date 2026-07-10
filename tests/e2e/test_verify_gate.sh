#!/bin/sh
# E2E: claude/hooks/verify-gate-pretooluse.sh (+ verify-gate-check.py)
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/claude/hooks/verify-gate-pretooluse.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-verify-gate-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP"
export VERIFY_GATE_LOG="$TMP/gate.log"

# The gate only fires on work-org repos, so pin the org list and target a work-org repo
# via `-R` - otherwise the result depends on whatever remote this checkout happens to have.
export VERIFY_GATE_WORK_ORGS=VantaInc
WORK_REPO="VantaInc/obsidian"

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
Ran e2e; all green. Tested manually in staging.'

VERIFY_BODY='## Verification
Ran the tests, e2e passed.'

NO_VERIFY_BODY='## Notes
Independent reviewer subagent looked at the diff.'

ROUTINE_ONLY_BODY='## Testing
Unit tests, typecheck, lint, and CI passed.'

CONFIRMED_ROUTINE_BODY='## Testing
Confirmed unit tests, typecheck, lint, and CI passed.'

EMPTY_TESTING_BODY='## Testing'

CONTEXT_ONLY_BODY='## Motivation
The production bug was confirmed in staging.'

DOCS_CONTEXT_ONLY_BODY='## Motivation
No code change to runtime behavior.'

USEFUL_TESTING_BODY='## Testing
Confirmed the failure path in staging and reproduced the fix end to end.'

DOCS_BODY='## Summary
Typo fix.
## Verification
Docs only, no runtime.'

# --- non-PR bash passes untouched ---
run_cmd 'ls -la' 0 'plain ls'
run_cmd 'git status && echo done' 0 'compound non-pr'

# --- gh pr create with verification evidence -> allow ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$GOOD_BODY'" 0 'full body inline'

# --- no grading section is required -> allow ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$VERIFY_BODY'" 0 'verification without grading'

# --- missing verification → block ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$NO_VERIFY_BODY'" 2 'missing verification'

# --- routine CI checks are not reviewer-useful evidence -> block ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$ROUTINE_ONLY_BODY'" 2 'routine checks only'

# --- a generic verb does not turn routine CI checks into useful evidence -> block ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$CONFIRMED_ROUTINE_BODY'" 2 'confirmed routine checks'

# --- an empty template heading is not evidence -> block ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$EMPTY_TESTING_BODY'" 2 'empty testing section'

# --- evidence words outside the Testing section do not satisfy the gate -> block ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$CONTEXT_ONLY_BODY'" 2 'context words outside testing'

# --- docs-only wording outside the Testing section does not satisfy the gate -> block ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$DOCS_CONTEXT_ONLY_BODY'" 2 'docs wording outside testing'

# --- action-result evidence inside Testing satisfies the gate -> allow ---
run_cmd "gh pr create -R $WORK_REPO --title t --body '$USEFUL_TESTING_BODY'" 0 'useful testing evidence'

# --- no body at all → block ---
run_cmd "gh pr create -R $WORK_REPO --title t" 2 'no body'

# --- docs-only body satisfies (scaled bar) → allow ---
run_cmd "gh pr create -R $WORK_REPO --body '$DOCS_BODY'" 0 'docs-only body'

# --- non-work-org repo → gate skips entirely, even with a bad body → allow ---
run_cmd "gh pr create -R octocat/personal --title t" 0 'personal repo skips gate'

# --- kill switch: bad body but VERIFY_GATE=off → allow ---
_json=$(CMD="gh pr create --title t" python3 -c 'import json,os;print(json.dumps({"tool_input":{"command":os.environ["CMD"]}}))')
if ! printf '%s' "$_json" | VERIFY_GATE=off bash "$HOOK" >/dev/null 2>&1; then
  fail "[kill switch] expected exit 0"
fi

# --- malformed hook JSON → fail open (allow) ---
if ! printf '%s' '{ not json' | bash "$HOOK" >/dev/null 2>&1; then
  fail "[malformed json] expected fail-open exit 0"
fi

# --- --body-file with verification -> allow ---
printf '%s' "$GOOD_BODY" >"$TMP/body.md"
run_cmd "gh pr create -R $WORK_REPO --title t --body-file $TMP/body.md" 0 'body-file allow'

# --- --body-file without grading -> allow ---
printf '%s' "$VERIFY_BODY" >"$TMP/body2.md"
run_cmd "gh pr create -R $WORK_REPO --title t --body-file $TMP/body2.md" 0 'body-file without grading'

# --- --fill (un-inspectable) → fail open (allow), don't false-block ---
run_cmd "gh pr create -R $WORK_REPO --fill" 0 'fill allow'

# --- --body-file that doesn't exist → fail open (can't inspect) → allow ---
run_cmd "gh pr create -R $WORK_REPO --title t --body-file $TMP/does-not-exist.md" 0 'unreadable body-file allow'

# --- check.py missing (lib present) → fail open, not a block from `python3 <missing>` exiting 2 ---
mkdir -p "$TMP/lone"
cp "$ROOT/claude/hooks/verify-gate-pretooluse.sh" "$ROOT/claude/hooks/verify-gate-lib.sh" "$TMP/lone/"
if ! printf '%s' '{"tool_input":{"command":"gh pr create --title t"}}' | bash "$TMP/lone/verify-gate-pretooluse.sh" >/dev/null 2>&1; then
  fail "[missing check.py] expected fail-open exit 0"
fi

echo "verify-gate: all cases passed"
exit 0
