#!/bin/sh
# E2E: Treehouse owns each checkout for the lifetime of its Herdr task workspace.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAUNCHER="$ROOT/herdr/new-agent-tab.sh"
TREEHOUSE_SHELL="$ROOT/herdr/treehouse-task-shell.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-herdr-treehouse-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

HOME_DIR="$TMP/home"
MAIN="$TMP/repo"
LINKED="$TMP/linked"
ACQUIRED="$TMP/treehouse-pool/1/repo"
HERDR_LOG="$TMP/herdr.log"
TREEHOUSE_LOG="$TMP/treehouse.log"
WORKSPACE_OPEN="$TMP/workspace-open"
TRANSPORT_FAILURE="$TMP/transport-failure"
TREEHOUSE_STARTED="$TMP/treehouse-started"
TREEHOUSE_RELEASE="$TMP/treehouse-release"
AGENT_READY="$TMP/agent-ready"
PROMPT_LOG="$TMP/prompt.log"
PROMPT_INPUT="$TMP/prompt-input.py"

mkdir -p "$HOME_DIR/.local/bin" "$MAIN" "${ACQUIRED%/*}"

git -C "$MAIN" init -q
git -C "$MAIN" config user.name test
git -C "$MAIN" config user.email test@example.com
printf 'fixture\n' > "$MAIN/fixture.txt"
git -C "$MAIN" add fixture.txt
git -C "$MAIN" commit -qm fixture
git -C "$MAIN" worktree add --detach "$LINKED" >/dev/null
git -C "$MAIN" worktree add --detach "$ACQUIRED" >/dev/null

cat > "$TMP/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
case "$1 $2" in
  "workspace create")
    : > "$FAKE_WORKSPACE_OPEN"
    printf '%s\n' '{"result":{"workspace":{"workspace_id":"test-workspace"},"tab":{"tab_id":"test-tab"},"root_pane":{"pane_id":"test-pane"}}}'
    ;;
  "workspace get")
    if [ -e "$FAKE_TRANSPORT_FAILURE" ]; then
      printf '%s\n' 'server unavailable' >&2
      exit 1
    fi
    if [ -e "$FAKE_WORKSPACE_OPEN" ]; then
      printf '%s\n' '{"result":{"workspace":{"workspace_id":"test-workspace"}}}'
    else
      printf '%s\n' '{"error":{"code":"workspace_not_found","message":"not found"}}'
      exit 1
    fi
    ;;
  "workspace close")
    rm -f "$FAKE_WORKSPACE_OPEN"
    ;;
  "workspace report-metadata")
    if [ -e "${FAKE_METADATA_FAILURE:-}" ]; then exit 10; fi
    ;;
  "pane split")
    if [ -e "${FAKE_SPLIT_FAILURE:-}" ]; then exit 7; fi
    printf '%s\n' '{"result":{"pane":{"pane_id":"test-editor"}}}'
    ;;
  "wait output")
    [ "$#" -eq 7 ] || exit 8
    : > "$FAKE_AGENT_READY"
    printf '%s\n' '{"result":{"matched_line":"Ask anything","pane_id":"test-pane"}}'
    ;;
  "pane run")
    [ "$#" -eq 4 ] || exit 8
    if [ -n "${FAKE_INITIAL_PROMPT:-}" ] && [ "$4" = "$FAKE_INITIAL_PROMPT" ]; then
      [ -e "$FAKE_AGENT_READY" ] || exit 9
      printf '%s\0' "$4" >> "$FAKE_PROMPT_LOG"
    fi
    ;;
esac
EOF
chmod +x "$TMP/herdr"

cat > "$HOME_DIR/.local/bin/treehouse" <<'EOF'
#!/bin/sh
printf 'start cwd=%s shell=%s args=%s\n' "$PWD" "$SHELL" "$*" >> "$FAKE_TREEHOUSE_LOG"
: > "$FAKE_TREEHOUSE_STARTED"
if [ -e "${FAKE_TREEHOUSE_FAILURE:-}" ]; then exit 9; fi
if [ -n "${FAKE_TREEHOUSE_RELEASE:-}" ]; then
  while [ ! -e "$FAKE_TREEHOUSE_RELEASE" ]; do sleep 0.02; done
fi
(
  cd "$FAKE_ACQUIRED"
  TREEHOUSE_DIR="$FAKE_ACQUIRED" "$SHELL"
)
status=$?
printf 'returned status=%s\n' "$status" >> "$FAKE_TREEHOUSE_LOG"
# Real Treehouse records the child exit code but completes its return lifecycle.
exit 0
EOF
chmod +x "$HOME_DIR/.local/bin/treehouse"

cat > "$PROMPT_INPUT" <<'PY'
import os
import sys

sys.stdout.write(os.environ.get("FAKE_INITIAL_PROMPT", ""))
PY

cat > "$HOME_DIR/.local/bin/fzf" <<'EOF'
#!/bin/sh
case "$*" in
  *"Checkout > ")
    [ "${FAKE_FZF_CANCEL:-}" = "checkout" ] && exit 1
    printf '%s\n' "${FAKE_FZF_CHECKOUT:-Fresh Treehouse worktree}"
    ;;
  *"Primary pane > ") printf '%s\n' "${FAKE_FZF_PRIMARY:-Shell}" ;;
  *"Editor > ") printf '%s\n' "${FAKE_FZF_EDITOR:-No editor}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$HOME_DIR/.local/bin/fzf"

for command in opencode nvim; do
  cat > "$HOME_DIR/.local/bin/$command" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$HOME_DIR/.local/bin/$command"
done

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_log() { grep -F -- "$1" "$2" >/dev/null || fail "missing '$1' in $2"; }
assert_not_log() { ! grep -F -- "$1" "$2" >/dev/null || fail "unexpected '$1' in $2"; }
wait_for_log() {
  for _ in $(seq 1 500); do
    if grep -F -- "$1" "$2" >/dev/null 2>&1; then return 0; fi
    sleep 0.02
  done
  fail "timed out waiting for '$1' in $2"
}
wait_for_exit() {
  for _ in $(seq 1 500); do
    if ! kill -0 "$1" 2>/dev/null; then wait "$1"; return 0; fi
    sleep 0.02
  done
  fail "process $1 did not exit"
}
reset_state() {
  : > "$HERDR_LOG"
  : > "$TREEHOUSE_LOG"
  : > "$PROMPT_LOG"
  rm -f "$WORKSPACE_OPEN" "$TRANSPORT_FAILURE" "$TREEHOUSE_STARTED" "$TREEHOUSE_RELEASE" "$AGENT_READY" "$TMP/split-failure" "$TMP/metadata-failure"
}

export FAKE_HERDR_LOG="$HERDR_LOG"
export FAKE_TREEHOUSE_LOG="$TREEHOUSE_LOG"
export FAKE_ACQUIRED="$ACQUIRED"
export FAKE_WORKSPACE_OPEN="$WORKSPACE_OPEN"
export FAKE_TRANSPORT_FAILURE="$TRANSPORT_FAILURE"
export FAKE_TREEHOUSE_STARTED="$TREEHOUSE_STARTED"
export FAKE_AGENT_READY="$AGENT_READY"
export FAKE_PROMPT_LOG="$PROMPT_LOG"

# The prompt editor keeps Enter as a newline and submits the complete buffer on
# Ctrl+Enter while making that gesture visible in the popup.
python3 - "$ROOT/herdr/prompt-input.py" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

editor = sys.argv[1]
master, slave = pty.openpty()
process = subprocess.Popen(
    [sys.executable, editor],
    stdin=slave,
    stdout=subprocess.PIPE,
    stderr=slave,
    close_fds=True,
)
os.close(slave)

screen = b""
deadline = time.monotonic() + 5
while b"Ctrl+Enter: submit" not in screen and time.monotonic() < deadline:
    readable, _, _ = select.select([master], [], [], 0.1)
    if readable:
        screen += os.read(master, 4096)

if b"Ctrl+Enter: submit" not in screen:
    process.kill()
    raise SystemExit("prompt editor did not show its submit gesture")

os.write(master, b"Review 'quoted' input\rthen keep && literal\x1b[13;5u")
stdout, _ = process.communicate(timeout=5)
os.close(master)
expected = b"Review 'quoted' input\nthen keep && literal"
if stdout != expected:
    raise SystemExit(f"prompt editor returned {stdout!r}, expected {expected!r}")
PY

# Treehouse invokes the wrapper in the acquired checkout and remains the owner
# until Herdr confirms that the task workspace closed.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  "$LAUNCHER" --with-worktree --with-agent --with-editor > "$TMP/launcher.out" 2>&1 &
launcher_pid=$!

wait_for_log "workspace create --cwd $ACQUIRED --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1 --env TREEHOUSE_DIR=$ACQUIRED" "$HERDR_LOG"
wait_for_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=repo --token worktree=1" "$HERDR_LOG"
assert_log "start cwd=$MAIN shell=$TREEHOUSE_SHELL args=get" "$TREEHOUSE_LOG"
wait_for_log "tab rename test-tab agent" "$HERDR_LOG"
wait_for_log "pane split test-pane --direction right --ratio 0.5 --cwd $ACQUIRED --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1 --env TREEHOUSE_DIR=$ACQUIRED" "$HERDR_LOG"
wait_for_log "pane run test-pane cd '$ACQUIRED' && clear; opencode" "$HERDR_LOG"
wait_for_log "pane run test-editor cd '$ACQUIRED' && clear; nvim" "$HERDR_LOG"
wait_for_log "notification show Task workspace ready --body Setup finished without changing your current focus." "$HERDR_LOG"
assert_not_log "workspace focus test-workspace" "$HERDR_LOG"
kill -0 "$launcher_pid" 2>/dev/null || fail "Treehouse returned before workspace close"

# Transport loss is not a close signal. Ownership survives until two reachable
# workspace_not_found responses arrive.
: > "$TRANSPORT_FAILURE"
rm -f "$WORKSPACE_OPEN"
sleep 3
kill -0 "$launcher_pid" 2>/dev/null || fail "transport failure released the Treehouse checkout"
rm -f "$TRANSPORT_FAILURE"
wait_for_exit "$launcher_pid"
assert_log "returned status=0" "$TREEHOUSE_LOG"

# Ready workspaces always stay in the background, so navigation can never race
# with a late focus request.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  "$LAUNCHER" --with-worktree --without-agent --without-editor > "$TMP/background.out" 2>&1 &
background_pid=$!
wait_for_log "workspace create --cwd $ACQUIRED --no-focus" "$HERDR_LOG"
wait_for_log "notification show Task workspace ready --body Setup finished without changing your current focus." "$HERDR_LOG"
assert_not_log "workspace focus test-workspace" "$HERDR_LOG"
rm -f "$WORKSPACE_OPEN"
wait_for_exit "$background_pid"

# Current-checkout mode bypasses Treehouse and creates the task directly.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor
assert_log "workspace create --cwd $LINKED --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1" "$HERDR_LOG"
assert_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=repo --token worktree=linked" "$HERDR_LOG"
assert_not_log "treehouse get" "$TREEHOUSE_LOG"

# The primary checkout uses a stable name instead of repeating the repository.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$MAIN" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor
assert_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=repo --token worktree=primary" "$HERDR_LOG"

# Metadata is part of workspace setup; failure closes the partial workspace.
reset_state
: > "$TMP/metadata-failure"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_METADATA_FAILURE="$TMP/metadata-failure" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor >/dev/null 2>&1 \
  && fail "metadata reporting failure returned success"
assert_log "workspace close test-workspace" "$HERDR_LOG"

# The popup returns before Treehouse finishes provisioning. Releasing the fake
# setup later creates the workspace without blocking the selector.
reset_state
export FAKE_TREEHOUSE_RELEASE="$TREEHOUSE_RELEASE"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  timeout 2 "$LAUNCHER" --select || fail "selector waited for Treehouse setup"
for _ in $(seq 1 100); do
  [ -e "$TREEHOUSE_STARTED" ] && break
  sleep 0.02
done
[ -e "$TREEHOUSE_STARTED" ] || fail "detached Treehouse setup did not start"
assert_not_log "workspace create" "$HERDR_LOG"
: > "$TREEHOUSE_RELEASE"
wait_for_log "workspace create --cwd $ACQUIRED --no-focus" "$HERDR_LOG"
rm -f "$WORKSPACE_OPEN"
wait_for_log "returned status=0" "$TREEHOUSE_LOG"
unset FAKE_TREEHOUSE_RELEASE

# OpenCode selection captures a multiline prompt, waits for readiness, and
# submits the exact prompt once without focusing the new workspace.
reset_state
initial_prompt="Review 'quoted' input
then keep && literal"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_PROMPT_INPUT_PATH="$PROMPT_INPUT" \
FAKE_FZF_CHECKOUT="Current checkout" \
FAKE_FZF_PRIMARY="OpenCode" \
FAKE_INITIAL_PROMPT="$initial_prompt" \
  "$LAUNCHER" --select
wait_for_log "wait output test-pane --match Ask anything --timeout 30000" "$HERDR_LOG"
for _ in $(seq 1 500); do
  [ -s "$PROMPT_LOG" ] && break
  sleep 0.02
done
python3 - "$PROMPT_LOG" "$initial_prompt" <<'PY'
import sys

with open(sys.argv[1], "rb") as prompt_log:
    submissions = [value for value in prompt_log.read().split(b"\0") if value]
expected = sys.argv[2].encode()
if submissions != [expected]:
    raise SystemExit(f"prompt submissions were {submissions!r}, expected {[expected]!r}")
PY
assert_not_log "workspace focus test-workspace" "$HERDR_LOG"

# An empty prompt still launches OpenCode but does not wait or submit input.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_PROMPT_INPUT_PATH="$PROMPT_INPUT" \
FAKE_FZF_CHECKOUT="Current checkout" \
FAKE_FZF_PRIMARY="OpenCode" \
  "$LAUNCHER" --select
wait_for_log "pane run test-pane cd '$LINKED' && clear; opencode" "$HERDR_LOG"
assert_not_log "wait output" "$HERDR_LOG"
[ ! -s "$PROMPT_LOG" ] || fail "empty prompt was submitted"

# Treehouse acquisition failures are visible even though shortcut commands run
# detached without a usable stderr.
reset_state
: > "$TMP/treehouse-failure"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_TREEHOUSE_FAILURE="$TMP/treehouse-failure" \
  "$LAUNCHER" --with-worktree --without-agent --without-editor >/dev/null 2>&1 \
  && fail "Treehouse acquisition failure returned success"
assert_log "notification show New task workspace failed --body Treehouse could not prepare a task checkout" "$HERDR_LOG"
assert_not_log "workspace create" "$HERDR_LOG"

# A setup failure closes the partial workspace before Treehouse returns.
reset_state
: > "$TMP/split-failure"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_SPLIT_FAILURE="$TMP/split-failure" \
  "$LAUNCHER" --with-worktree --without-agent --with-editor >/dev/null 2>&1 \
  || fail "Treehouse launcher surfaced wrapper setup failure"
assert_log "workspace close test-workspace" "$HERDR_LOG"
assert_log "returned status=1" "$TREEHOUSE_LOG"

# Dirty closure is surfaced before normal Treehouse return handling takes over.
reset_state
printf 'dirty\n' > "$ACQUIRED/uncommitted.txt"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
TREEHOUSE_DIR="$ACQUIRED" \
DOTFILES_HERDR_WITH_AGENT=false \
DOTFILES_HERDR_WITH_EDITOR=false \
  "$LAUNCHER" --treehouse-ready > "$TMP/dirty.out" 2>&1 &
dirty_pid=$!
wait_for_log "workspace create --cwd $ACQUIRED --no-focus" "$HERDR_LOG"
rm -f "$WORKSPACE_OPEN"
wait_for_exit "$dirty_pid"
assert_log "notification show Task workspace preserved --body Uncommitted changes remain at $ACQUIRED" "$HERDR_LOG"
rm -f "$ACQUIRED/uncommitted.txt"

# Cancelling the selector still creates nothing.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_FZF_CANCEL=checkout \
  "$LAUNCHER" --select
[ ! -s "$HERDR_LOG" ] || fail "cancelled selector launched a workspace"
[ ! -s "$TREEHOUSE_LOG" ] || fail "cancelled selector launched Treehouse"

[ "$(git config --file "$ROOT/.gitconfig" --get fetch.prune)" = true ] \
  || fail "fetch.prune is not enabled"

python3 - "$ROOT/herdr/config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    rows = tomllib.load(config_file)["ui"]["sidebar"]["spaces"]["rows"]
expected = [["state_icon", "workspace"], ["$repo", "$worktree"]]
if rows != expected:
    raise SystemExit(f"space rows were {rows!r}, expected {expected!r}")
PY

echo "Herdr Treehouse tests passed."
