#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-agent-browser-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p \
    "$TMP/bin" \
    "$TMP/home/.agents/skills/chrome-devtools-axi" \
    "$TMP/home/.chrome-devtools-axi" \
    "$TMP/home/.chrome-devtools-axi/sessions/worker-1" \
    "$TMP/home/.local/share/agent-browser/bin" \
    "$TMP/home/.nvm"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    grep -qF "$2" "$1" || fail "$1 does not contain $2"
}

assert_excludes() {
    if grep -qF "$2" "$1"; then
        fail "$1 unexpectedly contains $2"
    fi
}

cat >"$TMP/bin/node" <<'EOF'
#!/bin/sh
major=$(cat "$FAKE_NODE_MAJOR_FILE")
if [ "${1:-}" = "-p" ]; then
    printf '%s\n' "$major"
else
    printf 'v%s.0.0\n' "$major"
fi
EOF

cat >"$TMP/bin/npm" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "--version" ]; then
    printf '%s\n' '11.0.0'
    exit 0
fi
printf 'npm %s\n' "$*" >>"$FAKE_LOG"
printf '%s\n' 'agent-browser 0.33.2' >"$FAKE_VERSION_FILE"
EOF

cat >"$TMP/home/.local/share/agent-browser/bin/agent-browser" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
    --version)
        cat "$FAKE_VERSION_FILE"
        ;;
    doctor)
        [ -f "$FAKE_BROWSER_MARKER" ]
        ;;
    install)
        printf 'agent-browser %s\n' "$*" >>"$FAKE_LOG"
        : >"$FAKE_BROWSER_MARKER"
        ;;
    *)
        printf 'unexpected agent-browser invocation: %s\n' "$*" >&2
        exit 1
        ;;
esac
EOF

cat >"$TMP/bin/npx" <<'EOF'
#!/bin/sh
set -eu
printf 'npx %s\n' "$*" >>"$FAKE_LOG"
if [ "${FAKE_FAIL_AXI_STOP:-0}" = "1" ] && [ "$*" = "-y chrome-devtools-axi stop" ]; then
    exit 1
fi
if [ "$*" = "-y chrome-devtools-axi stop" ] && \
        [ "${CHROME_DEVTOOLS_AXI_SESSION:-default}" = "external" ]; then
    exit 1
fi
EOF

cat >"$TMP/home/.nvm/nvm.sh" <<'EOF'
nvm() {
    printf 'nvm %s\n' "$*" >>"$FAKE_LOG"
    printf '%s\n' '24' >"$FAKE_NODE_MAJOR_FILE"
}
EOF

chmod +x "$TMP/bin/node" "$TMP/bin/npm" "$TMP/bin/npx" "$TMP/home/.local/share/agent-browser/bin/agent-browser"

PATH="$TMP/bin:$PATH"
HOME="$TMP/home"
NVM_DIR="$HOME/.nvm"
FAKE_LOG="$TMP/invocations.log"
FAKE_VERSION_FILE="$TMP/version"
FAKE_BROWSER_MARKER="$TMP/browser-installed"
FAKE_NODE_MAJOR_FILE="$TMP/node-major"
export PATH HOME NVM_DIR FAKE_LOG FAKE_VERSION_FILE FAKE_BROWSER_MARKER FAKE_NODE_MAJOR_FILE

printf '%s\n' 'agent-browser 0.32.0' >"$FAKE_VERSION_FILE"
printf '%s\n' '24' >"$FAKE_NODE_MAJOR_FILE"
: >"$FAKE_LOG"

# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/80-tools.sh
. "$ROOT/install.d/80-tools.sh"

resolve_script_dir() {
    printf '%s\n' "$ROOT"
}

OS=linux install_agent_browser >/dev/null
assert_contains "$FAKE_LOG" "npm install -g --prefix $HOME/.local/share/agent-browser agent-browser@0.33.2"
assert_contains "$FAKE_LOG" 'agent-browser install --with-deps'
[ "$(readlink "$HOME/.local/bin/agent-browser")" = "$HOME/.local/share/agent-browser/bin/agent-browser" ] \
    || fail "agent-browser binary was not exposed"
[ "$(readlink "$HOME/.agent-browser/config.json")" = "$ROOT/agent-browser/config.json" ] \
    || fail "agent-browser config was not linked"

: >"$FAKE_LOG"
OS=linux install_agent_browser >/dev/null
assert_excludes "$FAKE_LOG" 'npm install'
assert_excludes "$FAKE_LOG" 'agent-browser install'

: >"$FAKE_LOG"
rm -f "$FAKE_BROWSER_MARKER"
OS=macos install_agent_browser >/dev/null
assert_contains "$FAKE_LOG" 'agent-browser install'
assert_excludes "$FAKE_LOG" 'agent-browser install --with-deps'

: >"$FAKE_LOG"
FAKE_FAIL_AXI_STOP=1
CHROME_DEVTOOLS_AXI_SESSION=external
export FAKE_FAIL_AXI_STOP CHROME_DEVTOOLS_AXI_SESSION
if remove_chrome_devtools_axi >/dev/null; then
    fail "chrome-devtools-axi removal continued after stop failed"
fi
[ -d "$HOME/.chrome-devtools-axi" ] || fail "failed stop removed chrome-devtools-axi state"
assert_excludes "$FAKE_LOG" 'skills remove chrome-devtools-axi'

: >"$FAKE_LOG"
FAKE_FAIL_AXI_STOP=0
export FAKE_FAIL_AXI_STOP
remove_chrome_devtools_axi >/dev/null
[ ! -d "$HOME/.chrome-devtools-axi" ] || fail "chrome-devtools-axi state was not removed"
install_agent_skill "vercel-labs/agent-browser" "agent-browser" >/dev/null
cat >"$TMP/expected.log" <<'EOF'
npx -y chrome-devtools-axi stop
npx -y chrome-devtools-axi stop
npx skills remove chrome-devtools-axi --yes --global
npx skills add vercel-labs/agent-browser --agent claude-code cursor codex opencode --skill agent-browser --yes --global
EOF
cmp -s "$FAKE_LOG" "$TMP/expected.log" || fail "browser skill migration commands differ"

: >"$FAKE_LOG"
printf '%s\n' '23' >"$FAKE_NODE_MAJOR_FILE"
OS=linux install_node_if_missing >/dev/null
assert_contains "$FAKE_LOG" 'nvm install 24'
assert_contains "$FAKE_LOG" 'nvm alias default 24'
assert_contains "$FAKE_LOG" 'nvm use 24'
[ "$(cat "$FAKE_NODE_MAJOR_FILE")" = "24" ] || fail "NVM did not activate Node 24"

assert_contains "$ROOT/install.d/10-helpers.sh" 'https://deb.nodesource.com/setup_24.x'
assert_contains "$ROOT/agent-browser/config.json" '"idleTimeout": "15m"'
