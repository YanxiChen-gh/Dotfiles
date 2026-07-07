#!/bin/sh
# E2E: claude/hooks/pr-authoring-gate-pretooluse.sh (+ pr-authoring-gate-check.py)
#
# The gate judges the PR body with `claude -p`, which is non-deterministic and needs auth -
# unusable in CI. So we shim a fake `claude` on PATH that returns a canned verdict envelope
# keyed off a sentinel in the prompt. That makes every path here deterministic and offline;
# the real judge is verified manually (see the PR). We assert the plumbing: which commands
# reach the judge, verdict → exit code, and that every failure mode fails OPEN.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/claude/hooks/pr-authoring-gate-pretooluse.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-pr-authoring-gate-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin"
export PR_AUTHORING_GATE_LOG="$TMP/gate.log"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake claude: BLOATED sentinel → bloated verdict; EXIT1 sentinel → nonzero (judge failure);
# otherwise → clean verdict. Scans argv because the hook passes the body in the -p prompt.
cat >"$TMP/bin/claude" <<'FAKE'
#!/bin/sh
for a in "$@"; do
  case "$a" in
    *PAG_TEST_EXIT1*)   exit 1 ;;
    *PAG_TEST_BLOATED*) printf '%s' '{"type":"result","is_error":false,"result":"{\"bloated\": true, \"issues\": [\"narrates the diff file-by-file\"]}"}'; exit 0 ;;
  esac
done
printf '%s' '{"type":"result","is_error":false,"result":"{\"bloated\": false, \"issues\": []}"}'
FAKE
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

C="gh pr create"
E="gh pr edit"

# Feed a hook JSON whose tool_input.command is $1; assert exit code $2. Extra env can be prefixed.
run_cmd() {  # $1=command $2=expected_exit [$3=label]
  _cmd="$1"; _want="$2"; _label="${3:-$1}"
  _json=$(CMD="$_cmd" python3 -c 'import json,os;print(json.dumps({"tool_input":{"command":os.environ["CMD"]}}))')
  set +e
  printf '%s' "$_json" | bash "$HOOK" >/dev/null 2>&1
  _got=$?
  set -e
  [ "$_got" -eq "$_want" ] || fail "[$_label] expected exit $_want, got $_got"
}

# --- commands that never reach the judge → allow ---
run_cmd 'ls -la' 0 'plain ls'
run_cmd 'git status && echo done' 0 'compound non-pr'
run_cmd "$C --title t" 0 'create no body allow'
run_cmd "$C --fill" 0 'fill allow'
run_cmd "$E 5 --add-label security-risk-low" 0 'edit labels only allow'
run_cmd "$C --title t --body ''" 0 'empty body allow'

# --- judge reached: verdict drives exit ---
run_cmd "$C --title t --body 'Refactor X to Y so Z.'" 0 'clean body allow'
run_cmd "$C --title t --body 'PAG_TEST_BLOATED narrates everything'" 2 'bloated body block'
run_cmd "$E 7 --body 'PAG_TEST_BLOATED we used to X now Y'" 2 'edit bloated body block'

# --- --body-file path ---
printf '%s' 'PAG_TEST_BLOATED file body' >"$TMP/body.md"
run_cmd "$C --title t --body-file $TMP/body.md" 2 'body-file bloated block'
printf '%s' 'Clean structural change.' >"$TMP/clean.md"
run_cmd "$C --title t --body-file $TMP/clean.md" 0 'body-file clean allow'
run_cmd "$C --title t --body-file $TMP/does-not-exist.md" 0 'unreadable body-file allow'

# --- everything fails OPEN ---
run_cmd "$C --title t --body 'PAG_TEST_EXIT1 judge crashed'" 0 'judge failure fails open'
set +e
printf '%s' '{ not json' | bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] || fail "[malformed json] expected fail-open exit 0"
set -e

# --- kill switch: bloated body but gate off → allow ---
_json=$(CMD="$C --body 'PAG_TEST_BLOATED'" python3 -c 'import json,os;print(json.dumps({"tool_input":{"command":os.environ["CMD"]}}))')
set +e
printf '%s' "$_json" | PR_AUTHORING_GATE=off bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] || fail "[kill switch] expected exit 0"
set -e

# --- claude not on PATH → fail open (shell-level guard) ---
set +e
_json=$(CMD="$C --body 'PAG_TEST_BLOATED'" python3 -c 'import json,os;print(json.dumps({"tool_input":{"command":os.environ["CMD"]}}))')
printf '%s' "$_json" | env PATH="/usr/bin:/bin" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] || fail "[no claude] expected fail-open exit 0"
set -e

# --- check.py missing → fail open (not a block from `python3 <missing-file>` exiting 2) ---
cp "$HOOK" "$TMP/bin/lone-hook.sh"   # copy the entry alone; no check.py beside it
set +e
printf '%s' "$_json" | bash "$TMP/bin/lone-hook.sh" >/dev/null 2>&1
[ $? -eq 0 ] || fail "[missing check.py] expected fail-open exit 0"
set -e

echo "pr-authoring-gate: all cases passed"
exit 0
