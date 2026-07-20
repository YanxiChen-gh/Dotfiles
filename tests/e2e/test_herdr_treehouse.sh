#!/bin/sh
# E2E: herdr/new-agent-tab.sh primary-checkout and worktree handoff behavior.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAUNCHER="$ROOT/herdr/new-agent-tab.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-herdr-treehouse-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

HOME_DIR="$TMP/home"
MAIN="$TMP/repo"
LINKED="$TMP/linked"
ACQUIRED="$TMP/acquired"
HERDR_LOG="$TMP/herdr.log"
TREEHOUSE_LOG="$TMP/treehouse.log"
TAB_CREATE_STARTED="$TMP/tab-create-started"
TAB_CREATE_RELEASE="$TMP/tab-create-release"
TAB_CREATE_COMPLETED="$TMP/tab-create-completed"

mkdir -p "$HOME_DIR/.local/bin" "$MAIN" "$ACQUIRED"

git -C "$MAIN" init -q
git -C "$MAIN" config user.name test
git -C "$MAIN" config user.email test@example.com
printf 'fixture\n' > "$MAIN/fixture.txt"
git -C "$MAIN" add fixture.txt
git -C "$MAIN" commit -qm fixture
git -C "$MAIN" worktree add --detach "$LINKED" >/dev/null

cat > "$TMP/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
case "$1 $2" in
  "tab create")
    if [ -n "${FAKE_TAB_CREATE_STARTED:-}" ]; then
      : > "$FAKE_TAB_CREATE_STARTED"
      while [ ! -e "$FAKE_TAB_CREATE_RELEASE" ]; do sleep 0.02; done
    fi
    printf '%s\n' '{"result":{"root_pane":{"pane_id":"test-pane"}}}'
    if [ -n "${FAKE_TAB_CREATE_COMPLETED:-}" ]; then
      : > "$FAKE_TAB_CREATE_COMPLETED"
    fi
    ;;
  "pane get")
    printf '{"result":{"pane":{"foreground_cwd":"%s"}}}\n' "$FAKE_ACQUIRED"
    ;;
esac
EOF
chmod +x "$TMP/herdr"

cat > "$HOME_DIR/.local/bin/treehouse" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_TREEHOUSE_LOG"
EOF
chmod +x "$HOME_DIR/.local/bin/treehouse"

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

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_log() { grep -F -- "$1" "$2" >/dev/null || fail "missing '$1' in $2"; }

export FAKE_HERDR_LOG="$HERDR_LOG"
export FAKE_TREEHOUSE_LOG="$TREEHOUSE_LOG"
export FAKE_ACQUIRED="$ACQUIRED"

HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_WORKSPACE_ID=test-workspace \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  "$LAUNCHER" --with-worktree --without-agent --without-editor

assert_log "tab create --cwd $MAIN" "$HERDR_LOG"
assert_log "--label shell" "$HERDR_LOG"
assert_log "pane run test-pane cd '$MAIN' && treehouse get" "$HERDR_LOG"
assert_log "pane get test-pane" "$HERDR_LOG"
[ ! -s "$TREEHOUSE_LOG" ] || fail "launcher queried global Treehouse status"

: > "$HERDR_LOG"

HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_WORKSPACE_ID=test-workspace \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
FAKE_FZF_CANCEL=checkout \
  "$LAUNCHER" --select
[ ! -s "$HERDR_LOG" ] || fail "cancelled selector launched a tab"

: > "$HERDR_LOG"

HOME="$HOME_DIR" \
HERDR_BIN_PATH="$TMP/herdr" \
HERDR_ACTIVE_WORKSPACE_ID=test-workspace \
HERDR_ACTIVE_PANE_CWD="$LINKED" \
  "$LAUNCHER" --without-worktree --without-agent --without-editor

assert_log "tab create --cwd $LINKED" "$HERDR_LOG"
if grep -F -- "treehouse get" "$HERDR_LOG" >/dev/null; then
  fail "current-checkout mode launched Treehouse"
fi

: > "$HERDR_LOG"

printf 'picked tab\n' | \
  HOME="$HOME_DIR" \
  HERDR_BIN_PATH="$TMP/herdr" \
  HERDR_ACTIVE_WORKSPACE_ID=test-workspace \
  HERDR_ACTIVE_PANE_CWD="$LINKED" \
  FAKE_TAB_CREATE_STARTED="$TAB_CREATE_STARTED" \
  FAKE_TAB_CREATE_RELEASE="$TAB_CREATE_RELEASE" \
  timeout 2 "$LAUNCHER" --select \
  || fail "selector waited for detached tab setup"

for _ in $(seq 1 100); do
  [ -e "$TAB_CREATE_STARTED" ] && break
  sleep 0.02
done
[ -e "$TAB_CREATE_STARTED" ] || fail "detached launcher did not start tab creation"
assert_log "tab create --cwd $MAIN --focus --workspace test-workspace --label picked tab" "$HERDR_LOG"

: > "$TAB_CREATE_RELEASE"
for _ in $(seq 1 100); do
  if grep -F -- "pane get test-pane" "$HERDR_LOG" >/dev/null; then break; fi
  sleep 0.02
done
assert_log "pane get test-pane" "$HERDR_LOG"
assert_log "pane run test-pane cd '$MAIN' && treehouse get" "$HERDR_LOG"

: > "$HERDR_LOG"

printf '\n' | \
  HOME="$HOME_DIR" \
  HERDR_BIN_PATH="$TMP/herdr" \
  HERDR_ACTIVE_WORKSPACE_ID=test-workspace \
  HERDR_ACTIVE_PANE_CWD="$LINKED" \
  FAKE_FZF_CHECKOUT="Current checkout" \
  FAKE_TAB_CREATE_COMPLETED="$TAB_CREATE_COMPLETED" \
  timeout 2 "$LAUNCHER" --select \
  || fail "blank-label selector failed"

for _ in $(seq 1 100); do
  [ -e "$TAB_CREATE_COMPLETED" ] && break
  sleep 0.02
done
[ -e "$TAB_CREATE_COMPLETED" ] || fail "blank-label tab was not created"
assert_log "tab create --cwd $LINKED --focus --workspace test-workspace" "$HERDR_LOG"
if grep -F -- "--label" "$HERDR_LOG" >/dev/null; then
  fail "blank selected label was replaced with a default"
fi

[ "$(git config --file "$ROOT/.gitconfig" --get fetch.prune)" = true ] \
  || fail "fetch.prune is not enabled"

echo "Herdr Treehouse tests passed."
