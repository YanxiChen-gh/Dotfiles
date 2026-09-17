#!/bin/sh
# E2E: Treehouse owns each checkout for the lifetime of its Herdr task workspace.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
unset OMP_EXPERIMENT
LAUNCHER="$ROOT/herdr/new-agent-tab.sh"
TREEHOUSE_SHELL="$ROOT/herdr/treehouse-task-shell.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-herdr-treehouse-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

HOME_DIR="$TMP/home"
MAIN="$TMP/repo"
LINKED="$TMP/linked"
QUOTED_LINKED="$TMP/linked'quoted"
ACQUIRED="$TMP/treehouse-pool-with-a-deliberately-long-checkout-name-for-token-boundary-coverage/1/repo"
TREEHOUSE_STATE="${ACQUIRED%/1/repo}/treehouse-state.json"
NEWLINE_POOL="$TMP/treehouse-newline"
NEWLINE_ACQUIRED="$NEWLINE_POOL/1/repo
checkout"
NEWLINE_TREEHOUSE_STATE="$NEWLINE_POOL/treehouse-state.json"
OTHER="$TMP/other"
OTHER_ACQUIRED="$TMP/other-treehouse/1/other"
CONFIGURED_ROOT="$TMP/configured-root"
CONFIGURED_REPO="$CONFIGURED_ROOT/configured"
CANONICAL_ROOT="$TMP/canonical-home"
CANONICAL_REPO="$CANONICAL_ROOT/canonical"
CLONE_ROOT="$TMP/clone-root"
CLONED_REPO="$CLONE_ROOT/cloned-repo"
NESTED_CLONE_ROOT="$MAIN/clone-root"
NESTED_CLONED_REPO="$NESTED_CLONE_ROOT/cloned-repo"
LOCAL_DEFAULT_HOME="$HOME_DIR/workspaces"
LOCAL_CLONED_REPO="$LOCAL_DEFAULT_HOME/cloned-repo"
DEEP_HOME_PARENT="$TMP/missing-parent"
DEEP_REPO_HOME="$DEEP_HOME_PARENT/nested-home"
DEEP_CLONED_REPO="$DEEP_REPO_HOME/cloned-repo"
IMPLICIT_ROOT="$TMP/implicit-root"
IMPLICIT_REPO="$IMPLICIT_ROOT/implicit"
NESTED_DISCOVERY_ROOT="$MAIN/discovery-root"
NESTED_NON_REPO="$NESTED_DISCOVERY_ROOT/not-a-repository"
DUPLICATE_ROOT_A="$TMP/duplicate-a"
DUPLICATE_ROOT_B="$TMP/duplicate-b"
DUPLICATE_REPO_A="$DUPLICATE_ROOT_A/shared"
DUPLICATE_REPO_B="$DUPLICATE_ROOT_B/shared"
ROOT_MISSING_HOME="/dotfiles-e2e-herdr-root-home-$$"
HERDR_LOG="$TMP/herdr.log"
TREEHOUSE_LOG="$TMP/treehouse.log"
HERDR_STATE="$TMP/herdr-state"
WORKSPACE_OPEN="$HERDR_STATE/test-workspace.open"
WORKSPACE_LIST="$TMP/workspace-list.json"
WORKSPACE_LIST_FAILURE="$TMP/workspace-list-failure"
TRANSPORT_FAILURE="$TMP/transport-failure"
TREEHOUSE_STARTED="$TMP/treehouse-started"
TREEHOUSE_RELEASE="$TMP/treehouse-release"
AGENT_READY="$TMP/agent-ready"
PROMPT_LOG="$TMP/prompt.log"
PROMPT_INPUT="$TMP/prompt-input.py"
FZF_INPUT_LOG="$TMP/fzf-input.log"
FZF_FIRST_INPUT="$TMP/fzf-first-input"
GH_LOG="$TMP/gh.log"

mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.omp/agent" "$MAIN" "$OTHER" "${ACQUIRED%/*}" "${NEWLINE_ACQUIRED%/*}" "${OTHER_ACQUIRED%/*}" "$CONFIGURED_REPO" "$CANONICAL_REPO" "$IMPLICIT_REPO" "$NESTED_NON_REPO" "$DUPLICATE_REPO_A" "$DUPLICATE_REPO_B" "$CLONE_ROOT" "$HERDR_STATE"
: > "$HOME_DIR/.omp/agent/.dotfiles-ready"

git -C "$MAIN" init -q
git -C "$MAIN" config user.name test
git -C "$MAIN" config user.email test@example.com
printf 'fixture\n' > "$MAIN/fixture.txt"
git -C "$MAIN" add fixture.txt
git -C "$MAIN" commit -qm fixture
git -C "$MAIN" worktree add --detach "$LINKED" >/dev/null
git -C "$MAIN" worktree add --detach "$QUOTED_LINKED" >/dev/null
git -C "$MAIN" worktree add --detach "$ACQUIRED" >/dev/null
git -C "$MAIN" worktree add --detach "$NEWLINE_ACQUIRED" >/dev/null

git -C "$OTHER" init -q
git -C "$OTHER" config user.name test
git -C "$OTHER" config user.email test@example.com
printf 'other\n' > "$OTHER/fixture.txt"
git -C "$OTHER" add fixture.txt
git -C "$OTHER" commit -qm fixture
git -C "$OTHER" worktree add --detach "$OTHER_ACQUIRED" >/dev/null

git -C "$CONFIGURED_REPO" init -q
git -C "$CONFIGURED_REPO" config user.name test
git -C "$CONFIGURED_REPO" config user.email test@example.com
printf 'configured\n' > "$CONFIGURED_REPO/fixture.txt"
git -C "$CONFIGURED_REPO" add fixture.txt
git -C "$CONFIGURED_REPO" commit -qm fixture

git -C "$CANONICAL_REPO" init -q
git -C "$CANONICAL_REPO" config user.name test
git -C "$CANONICAL_REPO" config user.email test@example.com
printf 'canonical\n' > "$CANONICAL_REPO/fixture.txt"
git -C "$CANONICAL_REPO" add fixture.txt
git -C "$CANONICAL_REPO" commit -qm fixture

git -C "$IMPLICIT_REPO" init -q
git -C "$IMPLICIT_REPO" config user.name test
git -C "$IMPLICIT_REPO" config user.email test@example.com
printf 'implicit\n' > "$IMPLICIT_REPO/fixture.txt"
git -C "$IMPLICIT_REPO" add fixture.txt
git -C "$IMPLICIT_REPO" commit -qm fixture

for repository in "$DUPLICATE_REPO_A" "$DUPLICATE_REPO_B"; do
  git -C "$repository" init -q
  git -C "$repository" config user.name test
  git -C "$repository" config user.email test@example.com
  printf 'duplicate\n' > "$repository/fixture.txt"
  git -C "$repository" add fixture.txt
  git -C "$repository" commit -qm fixture
done
ACQUIRED_CHECKOUT_ID=$(printf '%s' "$ACQUIRED" | git hash-object --stdin)
LINKED_CHECKOUT_ID=$(printf '%s' "$LINKED" | git hash-object --stdin)
MAIN_CHECKOUT_ID=$(printf '%s' "$MAIN" | git hash-object --stdin)
OTHER_ACQUIRED_CHECKOUT_ID=$(printf '%s' "$OTHER_ACQUIRED" | git hash-object --stdin)
OTHER_CHECKOUT_ID=$(printf '%s' "$OTHER" | git hash-object --stdin)
CLONED_CHECKOUT_ID=$(printf '%s' "$CLONED_REPO" | git hash-object --stdin)
if [ "${#ACQUIRED}" -le 80 ]; then
  echo "FAIL: acquired checkout path does not exercise Herdr's token boundary" >&2
  exit 1
fi

cat > "$TMP/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
workspace_id="${FAKE_WORKSPACE_ID:-test-workspace}"
if [ "$workspace_id" = "test-workspace" ]; then
  tab_id="test-tab"
  pane_id="test-pane"
  editor_id="test-editor"
else
  tab_id="$workspace_id-tab"
  pane_id="$workspace_id-pane"
  editor_id="$workspace_id-editor"
fi
case "$1 $2" in
  "workspace create")
    : > "$FAKE_HERDR_STATE/$workspace_id.open"
    printf '%s\n' "{\"result\":{\"workspace\":{\"workspace_id\":\"$workspace_id\"},\"tab\":{\"tab_id\":\"$tab_id\"},\"root_pane\":{\"pane_id\":\"$pane_id\"}}}"
    ;;
  "workspace get")
    if [ -e "$FAKE_TRANSPORT_FAILURE" ]; then
      printf '%s\n' 'server unavailable' >&2
      exit 1
    fi
    if [ -e "$FAKE_HERDR_STATE/$3.open" ]; then
      printf '%s\n' "{\"result\":{\"workspace\":{\"workspace_id\":\"$3\"}}}"
    else
      printf '%s\n' '{"error":{"code":"workspace_not_found","message":"not found"}}'
      exit 1
    fi
    ;;
  "workspace list")
    if [ -e "$FAKE_WORKSPACE_LIST_FAILURE" ]; then
      printf '%s\n' 'server unavailable' >&2
      exit 1
    fi
    if [ -e "$FAKE_WORKSPACE_LIST" ]; then
      cat "$FAKE_WORKSPACE_LIST"
    else
      printf '%s\n' '{"result":{"type":"workspace_list","workspaces":[]}}'
    fi
    ;;
  "workspace close")
    rm -f "$FAKE_HERDR_STATE/$3.open"
    ;;
  "workspace report-metadata")
    if [ -e "${FAKE_METADATA_FAILURE:-}" ]; then exit 10; fi
    ;;
  "pane split")
    if [ -e "${FAKE_SPLIT_FAILURE:-}" ]; then exit 7; fi
    printf '%s\n' "{\"result\":{\"pane\":{\"pane_id\":\"$editor_id\"}}}"
    ;;
  "wait output")
    [ "$#" -eq 7 ] || exit 8
    : > "$FAKE_AGENT_READY"
    printf '%s\n' "{\"result\":{\"matched_line\":\"Ask anything\",\"pane_id\":\"$pane_id\"}}"
    ;;
  "pane run")
    [ "$#" -eq 4 ] || exit 8
    if [ -n "${FAKE_INITIAL_PROMPT:-}" ] && [ "$4" = "$FAKE_INITIAL_PROMPT" ]; then
      [ -e "$FAKE_AGENT_READY" ] || exit 9
      printf '%s\0' "$4" >> "$FAKE_PROMPT_LOG"
    fi
    case "$4" in
      *"; env PI_FORCE_HYPERLINKS=1 omp @"*) sh -c "$4" >/dev/null 2>&1 & ;;
    esac
    ;;
esac
EOF
chmod +x "$TMP/herdr"

cat > "$HOME_DIR/.local/bin/treehouse" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "status" ] && [ "${2:-}" = "--json" ]; then
  printf 'status cwd=%s args=%s\n' "$PWD" "$*" >> "$FAKE_TREEHOUSE_LOG"
  printf '%s\n' "[{\"name\":\"1\",\"path\":\"$FAKE_ACQUIRED\",\"status\":\"in-use\",\"lease_id\":\"\",\"lease_holder\":\"\",\"leased_at\":null,\"processes\":[]}]"
  exit 0
fi
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
  *"Repository > "*)
    if [ -n "${FAKE_FZF_FIRST_INPUT:-}" ]; then
      IFS= read -r first_input || true
      printf '%s\n' "$first_input" > "$FAKE_FZF_FIRST_INPUT"
      if [ "${FAKE_FZF_SELECT_FIRST_INPUT:-}" = "true" ]; then
        printf '%s\n' "$first_input"
        exit 0
      fi
      exit 1
    fi
    input=$(cat)
    printf '%s\n' "$input" >> "$FAKE_FZF_INPUT_LOG"
    [ "${FAKE_FZF_CANCEL:-}" = "repository" ] && exit 1
    wanted="${FAKE_FZF_REPOSITORY:-$FAKE_CURRENT_REPOSITORY}"
    selection=$(printf '%s\n' "$input" | awk -F '\t' -v wanted="$wanted" '$2 == wanted { print; exit }')
    [ -n "$selection" ] || exit 1
    printf '%s\n' "$selection"
    ;;
  *"Repository path > "*)
    printf '%s\n' "${FAKE_FZF_REPOSITORY_PATH:-}"
    ;;
  *"GitHub repository > "*)
    printf '%s\n' "${FAKE_FZF_GITHUB_REPOSITORY:-}"
    ;;
  *"Repo home > "*)
    input=$(cat)
    printf '%s\n' "$input" >> "$FAKE_FZF_INPUT_LOG"
    wanted="${FAKE_FZF_REPO_HOME:-}"
    selection=$(printf '%s\n' "$input" | awk -F '\t' -v wanted="$wanted" '$2 == wanted { print; exit }')
    [ -n "$selection" ] || exit 1
    printf '%s\n' "$selection"
    ;;
  *"Checkout > "*)
    input=$(cat)
    printf '%s\n' "$input" >> "$FAKE_FZF_INPUT_LOG"
    [ "${FAKE_FZF_CANCEL:-}" = "checkout" ] && exit 1
    printf '%s\n' "${FAKE_FZF_CHECKOUT:-Fresh Treehouse worktree}"
    ;;
  *"Primary pane > ") printf '%s\n' "${FAKE_FZF_PRIMARY:-Shell}" ;;
  *"Editor > ") printf '%s\n' "${FAKE_FZF_EDITOR:-No editor}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$HOME_DIR/.local/bin/fzf"

cat > "$HOME_DIR/.local/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
case "$1 $2" in
  "repo view")
    [ "${FAKE_GH_FAILURE:-}" != "view" ] || exit 1
    if [ "${3:-}" = "--json" ]; then
      name_with_owner="${FAKE_GH_LOCAL_NAME_WITH_OWNER:-VantaInc/parent-repo}"
    else
      name_with_owner="${FAKE_GH_NAME_WITH_OWNER:-VantaInc/cloned-repo}"
    fi
    printf '{"nameWithOwner":"%s","name":"%s"}\n' \
      "$name_with_owner" \
      "${FAKE_GH_NAME:-cloned-repo}"
    ;;
  "repo clone")
    [ "${FAKE_GH_FAILURE:-}" != "clone" ] || exit 1
    mkdir -p "$4"
    git -C "$4" init -q
    git -C "$4" remote add origin "https://github.com/$3.git"
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$HOME_DIR/.local/bin/gh"

for command in opencode nvim; do
  cat > "$HOME_DIR/.local/bin/$command" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$HOME_DIR/.local/bin/$command"
done

cat > "$HOME_DIR/.local/bin/omp" <<'EOF'
#!/bin/sh
[ "${FAKE_OMP_UNAVAILABLE:-}" != "1" ] || exit 127
case "${1:-}" in
  config)
    if [ "${2:-}" = "get" ] && [ "${3:-}" = "tui.hyperlinks" ]; then
      printf '%s\n' "${FAKE_OMP_HYPERLINKS_MODE:-auto}"
    fi
    ;;
  @*)
    python3 - "${1#@}" "$FAKE_PROMPT_LOG" <<'PY'
import sys

with open(sys.argv[1], "rb") as source, open(sys.argv[2], "wb") as target:
    target.write(source.read())
PY
    ;;
esac
EOF
chmod +x "$HOME_DIR/.local/bin/omp"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_log() {
  if ! grep -F -- "$1" "$2" >/dev/null; then
    cat "$2" >&2
    fail "missing '$1' in $2"
  fi
}
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
write_treehouse_state() {
  jq -n --arg path "$ACQUIRED" \
    '{worktrees: [{name: "1", path: $path}]}' > "$TREEHOUSE_STATE"
  jq -n --arg path "$NEWLINE_ACQUIRED" \
    '{worktrees: [{name: "1", path: $path}]}' > "$NEWLINE_TREEHOUSE_STATE"
}

reset_state() {
  : > "$HERDR_LOG"
  : > "$TREEHOUSE_LOG"
  : > "$PROMPT_LOG"
  : > "$FZF_INPUT_LOG"
  : > "$GH_LOG"
  write_treehouse_state
  rm -rf "$CLONED_REPO" "$NESTED_CLONE_ROOT" "$LOCAL_DEFAULT_HOME" "$DEEP_HOME_PARENT"
  rm -f "$HERDR_STATE"/*.open "$WORKSPACE_LIST" "$WORKSPACE_LIST_FAILURE" "$TRANSPORT_FAILURE" "$TREEHOUSE_STARTED" "$TREEHOUSE_RELEASE" "$AGENT_READY" "$TMP/split-failure" "$TMP/metadata-failure"
}

export FAKE_HERDR_LOG="$HERDR_LOG"
export FAKE_HERDR_STATE="$HERDR_STATE"
export FAKE_WORKSPACE_LIST="$WORKSPACE_LIST"
export FAKE_WORKSPACE_LIST_FAILURE="$WORKSPACE_LIST_FAILURE"
export FAKE_TREEHOUSE_LOG="$TREEHOUSE_LOG"
export FAKE_ACQUIRED="$ACQUIRED"
export FAKE_TRANSPORT_FAILURE="$TRANSPORT_FAILURE"
export FAKE_TREEHOUSE_STARTED="$TREEHOUSE_STARTED"
export FAKE_AGENT_READY="$AGENT_READY"
export FAKE_PROMPT_LOG="$PROMPT_LOG"
export FAKE_FZF_INPUT_LOG="$FZF_INPUT_LOG"
export FAKE_CURRENT_REPOSITORY="$MAIN"
export FAKE_GH_LOG="$GH_LOG"

# Enter inserts a newline and Ctrl+S reliably submits with terminal flow
# control disabled. Encoded Ctrl+Enter remains supported where available.
python3 - "$ROOT/herdr/prompt-input.py" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

editor = sys.argv[1]

def run_case(input_bytes, expected):
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
    while b"Ctrl+S: submit" not in screen and time.monotonic() < deadline:
        readable, _, _ = select.select([master], [], [], 0.1)
        if readable:
            screen += os.read(master, 4096)
    if b"Ctrl+S: submit" not in screen:
        process.kill()
        raise SystemExit("prompt editor did not show its submit gesture")
    os.write(master, input_bytes)
    stdout, _ = process.communicate(timeout=5)
    os.close(master)
    if stdout != expected:
        raise SystemExit(f"prompt editor returned {stdout!r}, expected {expected!r}")

run_case(b"plain input\rsecond line\x1b[13;5u", b"plain input\nsecond line")
run_case(b"kitty enter\x1b[13unext line\x1b[13;5u", b"kitty enter\nnext line")
run_case(b"ctrl enter\x1b[13;5u", b"ctrl enter")
run_case(b"ctrl s\rsubmit\x13", b"ctrl s\nsubmit")
run_case(b"kitty ctrl s\x1b[115;5u", b"kitty ctrl s")
run_case(b"kitty ctrl s event\x1b[115;5:1u", b"kitty ctrl s event")
run_case(b"xterm ctrl s\x1b[27;5;115~", b"xterm ctrl s")
run_case(b"discard me\x1b", b"")
run_case(b"discard me\x1b[27u", b"")
run_case(b"\x1b[200~leading\ninternal\ntrailing\n\x1b[201~\x1b[13;5u", b"leading\ninternal\ntrailing\n")
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
wait_for_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=repo --token worktree=1 --token checkout=$ACQUIRED_CHECKOUT_ID" "$HERDR_LOG"
assert_log "start cwd=$MAIN shell=$TREEHOUSE_SHELL args=get" "$TREEHOUSE_LOG"
wait_for_log "tab rename test-tab agent" "$HERDR_LOG"
wait_for_log "pane split test-pane --direction right --ratio 0.5 --cwd $ACQUIRED --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1 --env TREEHOUSE_DIR=$ACQUIRED" "$HERDR_LOG"
wait_for_log "pane run test-pane cd $ACQUIRED && clear; env PI_FORCE_HYPERLINKS=1 omp" "$HERDR_LOG"
wait_for_log "pane run test-editor cd $ACQUIRED && clear; nvim" "$HERDR_LOG"
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

# Closing an owner must not return its checkout while another Herdr workspace
# still reports that exact checkout.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  "$LAUNCHER" --with-worktree --without-agent --without-editor > "$TMP/shared-owner.out" 2>&1 &
shared_owner_pid=$!
wait_for_log "workspace create --cwd $ACQUIRED --no-focus" "$HERDR_LOG"
: > "$HERDR_STATE/sibling-workspace.open"
printf '%s\n' "{\"result\":{\"type\":\"workspace_list\",\"workspaces\":[{\"workspace_id\":\"sibling-workspace\",\"tokens\":{\"checkout\":\"$ACQUIRED_CHECKOUT_ID\"}}]}}" > "$WORKSPACE_LIST"
rm -f "$WORKSPACE_OPEN"
sleep 3
kill -0 "$shared_owner_pid" 2>/dev/null || fail "Treehouse returned while a sibling workspace still used its checkout"
printf '%s\n' '{"result":{"type":"workspace_list","workspaces":[]}}' > "$WORKSPACE_LIST"
rm -f "$HERDR_STATE/sibling-workspace.open"
wait_for_exit "$shared_owner_pid"
assert_log "returned status=0" "$TREEHOUSE_LOG"

# Workspace-list transport loss after the owner closes must retain Treehouse
# ownership until Herdr becomes reachable again.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  "$LAUNCHER" --with-worktree --without-agent --without-editor > "$TMP/list-failure-owner.out" 2>&1 &
list_failure_owner_pid=$!
wait_for_log "workspace create --cwd $ACQUIRED --no-focus" "$HERDR_LOG"
: > "$WORKSPACE_LIST_FAILURE"
rm -f "$WORKSPACE_OPEN"
sleep 3
kill -0 "$list_failure_owner_pid" 2>/dev/null || fail "workspace-list transport failure released the Treehouse checkout"
rm -f "$WORKSPACE_LIST_FAILURE"
wait_for_exit "$list_failure_owner_pid"
assert_log "returned status=0" "$TREEHOUSE_LOG"

# A workspace for another canonical checkout does not keep this Treehouse
# checkout in use, even when repository and worktree basenames could collide.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  "$LAUNCHER" --with-worktree --without-agent --without-editor > "$TMP/unrelated-owner.out" 2>&1 &
unrelated_owner_pid=$!
wait_for_log "workspace create --cwd $ACQUIRED --no-focus" "$HERDR_LOG"
printf '%s\n' "{\"result\":{\"type\":\"workspace_list\",\"workspaces\":[{\"workspace_id\":\"unrelated-workspace\",\"tokens\":{\"repo\":\"repo\",\"worktree\":\"1\",\"checkout\":\"$LINKED_CHECKOUT_ID\"}}]}}" > "$WORKSPACE_LIST"
rm -f "$WORKSPACE_OPEN"
wait_for_exit "$unrelated_owner_pid"
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
assert_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=repo --token worktree=linked --token checkout=$LINKED_CHECKOUT_ID" "$HERDR_LOG"
assert_not_log "treehouse get" "$TREEHOUSE_LOG"
assert_not_log "status cwd=" "$TREEHOUSE_LOG"

# A Treehouse pool checkout cannot host an independent Herdr workspace, even
# when the Treehouse executable is unavailable.
reset_state
mv "$HOME_DIR/.local/bin/treehouse" "$TMP/treehouse"
shared_status=0
HOME="$HOME_DIR" \
PATH="/usr/bin:/bin" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$ACQUIRED" \
FAKE_WORKSPACE_ID="sibling-workspace" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor > "$TMP/shared-rejected.out" 2>&1 \
  || shared_status=$?
mv "$TMP/treehouse" "$HOME_DIR/.local/bin/treehouse"
[ "$shared_status" -ne 0 ] \
  || fail "current-checkout mode created a sibling workspace in a Treehouse checkout"
assert_not_log "workspace create" "$HERDR_LOG"
assert_log "notification show New task workspace failed --body Current checkout is already managed by Treehouse; choose a fresh Treehouse worktree." "$HERDR_LOG"

# Managed checkout paths retain their record boundary even when they contain a newline.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$NEWLINE_ACQUIRED" \
FAKE_WORKSPACE_ID="newline-workspace" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor > "$TMP/newline-rejected.out" 2>&1 \
  && fail "newline Treehouse checkout created an independent workspace"
assert_not_log "workspace create" "$HERDR_LOG"
assert_log "notification show New task workspace failed --body Current checkout is already managed by Treehouse; choose a fresh Treehouse worktree." "$HERDR_LOG"

# A discovered Treehouse state file must fail closed when its shape is invalid.
reset_state
printf '%s\n' '{"worktrees":"invalid"}' > "$TREEHOUSE_STATE"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$ACQUIRED" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor > "$TMP/malformed-state.out" 2>&1 \
  && fail "malformed Treehouse state allowed a shared checkout"
assert_not_log "workspace create" "$HERDR_LOG"
assert_log "notification show New task workspace failed --body could not inspect Treehouse worktree ownership" "$HERDR_LOG"

# A present null state version is malformed rather than equivalent to omission.
reset_state
printf '%s\n' '{"version":null,"worktrees":[]}' > "$TREEHOUSE_STATE"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$ACQUIRED" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor > "$TMP/null-version.out" 2>&1 \
  && fail "null Treehouse state version allowed a shared checkout"
assert_not_log "workspace create" "$HERDR_LOG"
assert_log "notification show New task workspace failed --body could not inspect Treehouse worktree ownership" "$HERDR_LOG"

# The primary checkout uses a stable name instead of repeating the repository.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$MAIN" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor
assert_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=repo --token worktree=primary --token checkout=$MAIN_CHECKOUT_ID" "$HERDR_LOG"

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

# Repository discovery is stable across source checkouts, and selecting the
# current repository reaches checkout options without inspecting Treehouse.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_HOME="$CANONICAL_ROOT" \
HERDR_REPO_ROOTS="$CONFIGURED_ROOT" \
FAKE_FZF_CANCEL=checkout \
  "$LAUNCHER" --select
assert_log "$MAIN" "$FZF_INPUT_LOG"
assert_log "$CANONICAL_REPO" "$FZF_INPUT_LOG"
assert_log "$CONFIGURED_REPO" "$FZF_INPUT_LOG"
assert_not_log "$OTHER" "$FZF_INPUT_LOG"
assert_not_log "$LINKED" "$FZF_INPUT_LOG"
assert_not_log "$QUOTED_LINKED" "$FZF_INPUT_LOG"
assert_not_log "$ACQUIRED" "$FZF_INPUT_LOG"
assert_not_log "workspace create" "$HERDR_LOG"
assert_log "Current checkout" "$FZF_INPUT_LOG"
assert_not_log "status cwd=" "$TREEHOUSE_LOG"

# The repository picker renders its first action before slow Git discovery
# finishes, so opening the popup never waits for repository metadata.
reset_state
cat > "$HOME_DIR/.local/bin/git" <<'EOF'
#!/bin/sh
if [ -n "${FAKE_GIT_DELAY:-}" ] && [ ! -e "${FAKE_FZF_FIRST_INPUT:-}" ]; then
  sleep "$FAKE_GIT_DELAY"
fi
exec /usr/bin/git "$@"
EOF
chmod +x "$HOME_DIR/.local/bin/git"
rm -f "$FZF_FIRST_INPUT"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_HOME="$CANONICAL_ROOT" \
FAKE_FZF_FIRST_INPUT="$FZF_FIRST_INPUT" \
FAKE_FZF_SELECT_FIRST_INPUT=true \
FAKE_FZF_REPOSITORY_PATH="$CONFIGURED_REPO" \
FAKE_FZF_CANCEL=checkout \
FAKE_GIT_DELAY=3 \
  "$LAUNCHER" --select &
picker_pid=$!
for _ in $(seq 1 100); do
  [ -e "$FZF_FIRST_INPUT" ] && break
  sleep 0.02
done
if [ ! -e "$FZF_FIRST_INPUT" ]; then
  kill "$picker_pid" 2>/dev/null || true
  wait "$picker_pid" 2>/dev/null || true
  fail "repository picker waited for Git discovery"
fi
assert_log "+ Open local path..." "$FZF_FIRST_INPUT"
wait_for_exit "$picker_pid"
assert_log "Fresh Treehouse worktree" "$FZF_INPUT_LOG"
rm -f "$HOME_DIR/.local/bin/git" "$FZF_FIRST_INPUT"

# A repository home nested inside another checkout does not discover that
# enclosing checkout through ordinary child directories.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$OTHER" \
HERDR_REPO_HOME="$NESTED_DISCOVERY_ROOT" \
FAKE_FZF_CANCEL=repository \
  "$LAUNCHER" --select
assert_log "$OTHER" "$FZF_INPUT_LOG"
assert_not_log "$MAIN" "$FZF_INPUT_LOG"

# Repositories with the same basename remain distinguishable in the picker.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$MAIN" \
HERDR_REPO_HOME="$DUPLICATE_ROOT_A" \
HERDR_REPO_ROOTS="$DUPLICATE_ROOT_B" \
FAKE_FZF_CANCEL=repository \
  "$LAUNCHER" --select
assert_log "$(printf 'shared  %s\t%s' "$DUPLICATE_REPO_A" "$DUPLICATE_REPO_A")" "$FZF_INPUT_LOG"
assert_log "$(printf 'shared  %s\t%s' "$DUPLICATE_REPO_B" "$DUPLICATE_REPO_B")" "$FZF_INPUT_LOG"

# Empty migration-root entries are ignored rather than turning the launcher's
# working directory into an implicit repository root.
reset_state
(
  cd "$IMPLICIT_ROOT"
  HOME="$HOME_DIR" \
  HERDR_BIN_PATH="$TMP/herdr" \
  HERDR_ACTIVE_PANE_CWD="$LINKED" \
  HERDR_REPO_HOME="$CANONICAL_ROOT" \
  HERDR_REPO_ROOTS=":$CONFIGURED_ROOT::" \
  FAKE_FZF_CANCEL=checkout \
    "$LAUNCHER" --select
)
assert_not_log "$IMPLICIT_REPO" "$FZF_INPUT_LOG"
assert_log "$CONFIGURED_REPO" "$FZF_INPUT_LOG"
assert_not_log "workspace create" "$HERDR_LOG"

# Cloud markers select /workspaces even when an extra migration root is
# available, without relying on the host fixture's repository layout.
reset_state
HOME="$HOME_DIR" \
IS_ON_ONA=true \
CURSOR_CLOUD=0 \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_ROOTS="$CLONE_ROOT" \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="VantaInc/cloned-repo" \
FAKE_FZF_REPO_HOME="$CLONE_ROOT" \
FAKE_FZF_CANCEL=checkout \
  "$LAUNCHER" --select
assert_log "$(printf '/workspaces\t/workspaces')" "$FZF_INPUT_LOG"
assert_not_log "workspace create" "$HERDR_LOG"

# Missing repository homes directly under / keep one canonical leading slash.
reset_state
HOME="$HOME_DIR" \
HERDR_REPO_HOME="$ROOT_MISSING_HOME" \
HERDR_REPO_ROOTS="$CLONE_ROOT" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="VantaInc/cloned-repo" \
FAKE_FZF_REPO_HOME="$ROOT_MISSING_HOME" \
FAKE_FZF_CANCEL=checkout \
  "$LAUNCHER" --select
assert_log "$(printf '%s\t%s' "$ROOT_MISSING_HOME" "$ROOT_MISSING_HOME")" "$FZF_INPUT_LOG"

# Local fallback advertises $HOME/workspaces without creating it during
# discovery.
reset_state
HOME="$HOME_DIR" \
IS_ON_ONA=false \
CURSOR_CLOUD=0 \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_ROOTS="$CLONE_ROOT" \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="VantaInc/cloned-repo" \
FAKE_FZF_REPO_HOME="$CLONE_ROOT" \
FAKE_FZF_CANCEL=checkout \
  "$LAUNCHER" --select
assert_log "$(printf '%s\t%s' "$LOCAL_DEFAULT_HOME" "$LOCAL_DEFAULT_HOME")" "$FZF_INPUT_LOG"
[ ! -e "$LOCAL_DEFAULT_HOME" ] || fail "repository discovery created $LOCAL_DEFAULT_HOME"

# Clone creates a missing local fallback home only after the clone action is
# confirmed, then continues through the normal shared-checkout path.
reset_state
HOME="$HOME_DIR" \
IS_ON_ONA=false \
CURSOR_CLOUD=0 \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="VantaInc/cloned-repo" \
FAKE_FZF_CHECKOUT="Primary checkout" \
  "$LAUNCHER" --select
wait_for_log "repo clone VantaInc/cloned-repo $LOCAL_CLONED_REPO" "$GH_LOG"
wait_for_log "workspace create --cwd $LOCAL_CLONED_REPO --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1" "$HERDR_LOG"

# An explicit nested repo home remains selectable even when none of its
# directories exist yet; Clone creates the complete path.
reset_state
HOME="$HOME_DIR" \
IS_ON_ONA=false \
CURSOR_CLOUD=0 \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_HOME="$DEEP_REPO_HOME" \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="VantaInc/cloned-repo" \
FAKE_FZF_CHECKOUT="Primary checkout" \
  "$LAUNCHER" --select
wait_for_log "repo clone VantaInc/cloned-repo $DEEP_CLONED_REPO" "$GH_LOG"
wait_for_log "workspace create --cwd $DEEP_CLONED_REPO --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1" "$HERDR_LOG"


# Selecting another repository's shared checkout creates the workspace there
# without changing the source pane or involving Treehouse.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_HOME="$TMP" \
FAKE_FZF_REPOSITORY="$OTHER" \
FAKE_FZF_CHECKOUT="Primary checkout" \
  "$LAUNCHER" --select
wait_for_log "workspace create --cwd $OTHER --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1" "$HERDR_LOG"
wait_for_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=other --token worktree=primary --token checkout=$OTHER_CHECKOUT_ID" "$HERDR_LOG"
assert_not_log "treehouse get" "$TREEHOUSE_LOG"

# Selecting another repository's fresh checkout runs the existing Treehouse
# ownership bridge from that repository.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_TREEHOUSE_SHELL_PATH="$TREEHOUSE_SHELL" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_HOME="$TMP" \
FAKE_ACQUIRED="$OTHER_ACQUIRED" \
FAKE_FZF_REPOSITORY="$OTHER" \
FAKE_FZF_CHECKOUT="Fresh Treehouse worktree" \
  "$LAUNCHER" --select
wait_for_log "start cwd=$OTHER shell=$TREEHOUSE_SHELL args=get" "$TREEHOUSE_LOG"
wait_for_log "workspace create --cwd $OTHER_ACQUIRED --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1 --env TREEHOUSE_DIR=$OTHER_ACQUIRED" "$HERDR_LOG"
wait_for_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=other --token worktree=1 --token checkout=$OTHER_ACQUIRED_CHECKOUT_ID" "$HERDR_LOG"
rm -f "$WORKSPACE_OPEN"
wait_for_log "returned status=0" "$TREEHOUSE_LOG"

# Open local path accepts a repository outside the discovered list and then
# uses its primary checkout.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_FZF_REPOSITORY="__open__" \
FAKE_FZF_REPOSITORY_PATH="$CONFIGURED_REPO" \
FAKE_FZF_CHECKOUT="Primary checkout" \
  "$LAUNCHER" --select
wait_for_log "workspace create --cwd $CONFIGURED_REPO --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1" "$HERDR_LOG"
assert_not_log "treehouse get" "$TREEHOUSE_LOG"

# A managed source checkout reaches checkout selection without synchronously
# inspecting Treehouse ownership.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$ACQUIRED" \
FAKE_FZF_CANCEL=checkout \
  "$LAUNCHER" --select
assert_log "Current checkout" "$FZF_INPUT_LOG"
assert_not_log "status cwd=" "$TREEHOUSE_LOG"
assert_not_log "workspace create" "$HERDR_LOG"

# A managed source checkout stays selectable, then the detached state-file
# guard rejects it before workspace creation.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$ACQUIRED" \
FAKE_FZF_CHECKOUT="Current checkout" \
  "$LAUNCHER" --select
assert_log "Current checkout" "$FZF_INPUT_LOG"
assert_not_log "status cwd=" "$TREEHOUSE_LOG"
wait_for_log "notification show New task workspace failed --body Current checkout is already managed by Treehouse; choose a fresh Treehouse worktree." "$HERDR_LOG"
assert_not_log "workspace create" "$HERDR_LOG"

# Clone canonicalizes the GitHub reference, creates the primary checkout under
# the selected repo home, and continues through shared-checkout setup.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_HOME="$CLONE_ROOT" \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="https://github.com/VantaInc/cloned-repo" \
FAKE_FZF_REPO_HOME="$CLONE_ROOT" \
FAKE_FZF_CHECKOUT="Primary checkout" \
  "$LAUNCHER" --select
wait_for_log "repo view https://github.com/VantaInc/cloned-repo --json nameWithOwner,name" "$GH_LOG"
wait_for_log "repo clone VantaInc/cloned-repo $CLONED_REPO" "$GH_LOG"
wait_for_log "workspace create --cwd $CLONED_REPO --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1" "$HERDR_LOG"
wait_for_log "workspace report-metadata test-workspace --source dotfiles:checkout --token repo=cloned-repo --token worktree=primary --token checkout=$CLONED_CHECKOUT_ID" "$HERDR_LOG"

# Selecting an already-cloned matching repository reuses it instead of cloning
# again or rejecting the destination.
: > "$HERDR_LOG"
: > "$GH_LOG"
rm -f "$WORKSPACE_OPEN"
HOME="$HOME_DIR" \
HERDR_REPO_HOME="$CLONE_ROOT" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="VantaInc/cloned-repo" \
FAKE_FZF_REPO_HOME="$CLONE_ROOT" \
FAKE_FZF_CHECKOUT="Primary checkout" \
  "$LAUNCHER" --select
wait_for_log "repo view https://github.com/VantaInc/cloned-repo.git --json nameWithOwner" "$GH_LOG"
assert_not_log "repo clone" "$GH_LOG"
wait_for_log "workspace create --cwd $CLONED_REPO --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1" "$HERDR_LOG"


# Clone failure happens before Herdr workspace creation and surfaces the failed
# setup stage from the detached launcher.
reset_state
HOME="$HOME_DIR" \
HERDR_REPO_HOME="$CLONE_ROOT" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_GH_FAILURE=clone \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="VantaInc/cloned-repo" \
FAKE_FZF_REPO_HOME="$CLONE_ROOT" \
FAKE_FZF_CHECKOUT="Primary checkout" \
  "$LAUNCHER" --select
wait_for_log "notification show New task workspace failed --body GitHub could not clone VantaInc/cloned-repo." "$HERDR_LOG"
assert_not_log "workspace create" "$HERDR_LOG"

# A non-repository collision nested inside another matching repository is
# rejected instead of reusing the enclosing checkout.
reset_state
mkdir -p "$NESTED_CLONED_REPO"
git -C "$MAIN" remote add origin https://github.com/VantaInc/cloned-repo.git
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_REPO_HOME="$NESTED_CLONE_ROOT" \
FAKE_FZF_REPOSITORY="__clone__" \
FAKE_FZF_GITHUB_REPOSITORY="VantaInc/cloned-repo" \
FAKE_FZF_REPO_HOME="$NESTED_CLONE_ROOT" \
FAKE_FZF_CHECKOUT="Primary checkout" \
  "$LAUNCHER" --select
wait_for_log "notification show New task workspace failed --body Clone destination already exists and is not VantaInc/cloned-repo: $NESTED_CLONED_REPO" "$HERDR_LOG"
assert_not_log "repo clone" "$GH_LOG"
assert_not_log "workspace create" "$HERDR_LOG"
git -C "$MAIN" remote remove origin

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

# Successful process creation transfers prompt-file ownership immediately.
# A delayed detached shell must not trip a launcher handshake timeout.
reset_state
cat > "$HOME_DIR/.local/bin/bash" <<'EOF'
#!/bin/sh
sleep 3
exec /bin/bash "$@"
EOF
chmod +x "$HOME_DIR/.local/bin/bash"
delayed_prompt="start after delayed detached shell"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_PROMPT_INPUT_PATH="$PROMPT_INPUT" \
FAKE_FZF_CHECKOUT="Current checkout" \
FAKE_FZF_PRIMARY="omp" \
FAKE_INITIAL_PROMPT="$delayed_prompt" \
  timeout 5 /bin/bash "$LAUNCHER" --select \
  || fail "selector did not transfer launch ownership"
for _ in $(seq 1 500); do
  [ -s "$PROMPT_LOG" ] && break
  sleep 0.02
done
[ "$(cat "$PROMPT_LOG")" = "$delayed_prompt" ] \
  || fail "delayed launcher lost its initial prompt"
assert_not_log "New task workspace failed" "$HERDR_LOG"
rm -f "$HOME_DIR/.local/bin/bash"

# OpenCode selection captures a multiline prompt, waits for readiness, and
# submits the exact prompt once without focusing the new workspace.
reset_state
initial_prompt="Review 'quoted' input
then keep && literal"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_PROMPT_INPUT_PATH="$PROMPT_INPUT" \
OMP_EXPERIMENT=0 \
FAKE_FZF_CHECKOUT="Current checkout" \
FAKE_FZF_PRIMARY="opencode" \
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
HERDR_AGENT_CMD=opencode \
FAKE_FZF_CHECKOUT="Current checkout" \
FAKE_FZF_PRIMARY="opencode" \
  "$LAUNCHER" --select
wait_for_log "pane run test-pane cd $LINKED && clear; opencode" "$HERDR_LOG"
assert_not_log "wait output" "$HERDR_LOG"
[ ! -s "$PROMPT_LOG" ] || fail "empty prompt was submitted"

# OMP's persistent hyperlink opt-out must not be overridden by the Herdr launcher.
reset_state
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
HERDR_AGENT_CMD=omp \
FAKE_OMP_HYPERLINKS_MODE=off \
  "$LAUNCHER" --without-worktree --with-agent --without-editor
wait_for_log "pane run test-pane cd $LINKED && clear; omp" "$HERDR_LOG"
assert_not_log "PI_FORCE_HYPERLINKS" "$HERDR_LOG"

# A default-on environment still falls back to OpenCode when omp is unavailable.
reset_state
HOME="$HOME_DIR" \
PATH="/usr/bin:/bin" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_OMP_UNAVAILABLE=1 \
PI_CODING_AGENT_DIR="$TMP/missing-omp-agent" \
  "$LAUNCHER" --without-worktree --with-agent --without-editor
wait_for_log "pane run test-pane cd $LINKED && clear; opencode" "$HERDR_LOG"

# omp receives its initial prompt as an @file launch argument, so first-run
# setup can finish without a guessed readiness delay. File bytes stay exact.
reset_state
omp_prompt="leading
internal
trailing
"
HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_PANE_CWD="$QUOTED_LINKED" \
HERDR_PROMPT_INPUT_PATH="$PROMPT_INPUT" \
FAKE_FZF_CHECKOUT="Current checkout" \
FAKE_FZF_PRIMARY="omp" \
FAKE_INITIAL_PROMPT="$omp_prompt" \
  "$LAUNCHER" --select
wait_for_log "pane run test-pane cd $TMP/linked\\'quoted && clear; env PI_FORCE_HYPERLINKS=1 omp @" "$HERDR_LOG"
for _ in $(seq 1 500); do
  [ -s "$PROMPT_LOG" ] && break
  sleep 0.02
done
python3 - "$PROMPT_LOG" "$omp_prompt" <<'PY'
import sys

with open(sys.argv[1], "rb") as prompt_log:
    actual = prompt_log.read()
expected = sys.argv[2].encode()
if actual != expected:
    raise SystemExit(f"omp prompt was {actual!r}, expected {expected!r}")
PY
assert_not_log "wait output" "$HERDR_LOG"

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
FAKE_FZF_CANCEL=repository \
  "$LAUNCHER" --select
[ ! -s "$HERDR_LOG" ] || fail "cancelled selector launched a workspace"
[ ! -s "$TREEHOUSE_LOG" ] || fail "cancelled selector launched Treehouse"

[ "$(git config --file "$ROOT/.gitconfig" --get fetch.prune)" = true ] \
  || fail "fetch.prune is not enabled"

python3 - "$ROOT/herdr/config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
    rows = config["ui"]["sidebar"]["spaces"]["rows"]
expected = [["state_icon", "workspace"], ["$repo", "$worktree"]]
if rows != expected:
    raise SystemExit(f"space rows were {rows!r}, expected {expected!r}")
commands = [entry["command"] for entry in config["keys"]["command"]]
expected_commands = [
    "${DOTFILES_DIR:-$HOME/dotfiles}/herdr/new-agent-tab.sh --select",
    "${DOTFILES_DIR:-$HOME/dotfiles}/herdr/new-agent-tab.sh --with-editor",
]
if commands != expected_commands:
    raise SystemExit(f"shortcut commands were {commands!r}, expected {expected_commands!r}")
agent_rows = config["ui"]["sidebar"]["agents"]["rows_by_agent"]
if "omp" in agent_rows:
    raise SystemExit(f"redundant omp sidebar rows remain: {agent_rows['omp']!r}")
PY

echo "Herdr Treehouse tests passed."
