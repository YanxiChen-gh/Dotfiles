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
    printf '%s\n' '{"result":{"root_pane":{"pane_id":"test-pane"}}}'
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
assert_log "pane run test-pane cd '$MAIN' && treehouse get" "$HERDR_LOG"
assert_log "pane get test-pane" "$HERDR_LOG"
[ ! -s "$TREEHOUSE_LOG" ] || fail "launcher queried global Treehouse status"

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

[ "$(git config --file "$ROOT/.gitconfig" --get fetch.prune)" = true ] \
  || fail "fetch.prune is not enabled"

echo "Herdr Treehouse tests passed."
