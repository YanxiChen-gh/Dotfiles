#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/setup_work_google_workspace_auth.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-google-workspace-cli-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/home/.config/gws" "$TMP/npm-prefix/bin"

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

cat >"$TMP/bin/gws" <<'EOF'
#!/bin/sh
set -eu

if [ "${1:-}" = "--version" ]; then
    printf '%s\n' 'gws 9.9.9'
    exit 0
fi

exec "$FAKE_NPM_PREFIX/bin/gws" "$@"
EOF

cat >"$TMP/npm-prefix/bin/gws" <<'EOF'
#!/bin/sh
set -eu

if [ "${1:-}" = "--version" ]; then
    printf 'gws %s\n' "$(cat "$FAKE_VERSION_FILE")"
    exit 0
fi

if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
    if [ -f "$FAKE_LOGIN_STATE" ]; then
        printf '%s\n' "$FAKE_POST_LOGIN_STATUS"
    else
        printf '%s\n' "$FAKE_INITIAL_STATUS"
    fi
    exit 0
fi

if [ "${1:-}" = "auth" ] && [ "${2:-}" = "login" ]; then
    printf 'login' >>"$FAKE_LOG"
    shift 2
    for arg in "$@"; do
        printf ' <%s>' "$arg" >>"$FAKE_LOG"
    done
    printf '\n' >>"$FAKE_LOG"
    : >"$FAKE_LOGIN_STATE"
    exit 0
fi

if [ "${1:-}" = "auth" ] && [ "${2:-}" = "logout" ]; then
    printf 'logout\n' >>"$FAKE_LOG"
    rm -f "$FAKE_LOGIN_STATE"
    exit 0
fi

printf 'unexpected gws invocation: %s\n' "$*" >&2
exit 1
EOF

cat >"$TMP/bin/npm" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "prefix" ] && [ "${2:-}" = "-g" ]; then
    printf '%s\n' "$FAKE_NPM_PREFIX"
    exit 0
fi
if [ "${1:-}" = "--version" ]; then
    printf '%s\n' '11.0.0'
    exit 0
fi
printf 'npm %s\n' "$*" >>"$FAKE_LOG"
printf '%s\n' '0.22.5' >"$FAKE_VERSION_FILE"
EOF

chmod +x "$TMP/bin/gws" "$TMP/bin/npm" "$TMP/npm-prefix/bin/gws"

PATH="$TMP/bin:$PATH"
HOME="$TMP/home"
FAKE_VERSION_FILE="$TMP/gws-version"
FAKE_LOGIN_STATE="$TMP/logged-in"
FAKE_LOG="$TMP/invocations.log"
FAKE_NPM_PREFIX="$TMP/npm-prefix"
export PATH HOME FAKE_VERSION_FILE FAKE_LOGIN_STATE FAKE_LOG FAKE_NPM_PREFIX

required_scopes='https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/presentations,https://www.googleapis.com/auth/drive'
ready_status='{"token_valid":true,"user":"yanxi.chen@vanta.com","scopes":["https://www.googleapis.com/auth/documents","https://www.googleapis.com/auth/spreadsheets","https://www.googleapis.com/auth/presentations","https://www.googleapis.com/auth/drive","openid"]}'

# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/80-tools.sh
. "$ROOT/install.d/80-tools.sh"

printf '%s\n' '0.20.0' >"$FAKE_VERSION_FILE"
: >"$FAKE_LOG"
WORK_MACHINE=0 install_google_workspace_cli
[ ! -s "$FAKE_LOG" ] || fail "personal install invoked npm"

WORK_MACHINE=1 install_google_workspace_cli >/dev/null
assert_contains "$FAKE_LOG" 'npm install -g @googleworkspace/cli@0.22.5'
[ "$(cat "$FAKE_VERSION_FILE")" = "0.22.5" ] || fail "installer did not upgrade gws"
[ "$(readlink "$HOME/.local/bin/gws")" = "$FAKE_NPM_PREFIX/bin/gws" ] || fail "installer did not expose the pinned npm binary"

DOTFILES_DIR="$ROOT"
export DOTFILES_DIR
# shellcheck source=../../shell/work.sh
. "$ROOT/shell/work.sh"
[ "$(command -v gws)" = "$HOME/.local/bin/gws" ] || fail "work PATH did not prefer the managed gws binary"

: >"$FAKE_LOG"
WORK_MACHINE=1 install_google_workspace_cli >/dev/null
[ ! -s "$FAKE_LOG" ] || fail "matching gws version was reinstalled"

touch "$HOME/.config/gws/client_secret.json"
FAKE_INITIAL_STATUS="$ready_status"
FAKE_POST_LOGIN_STATUS="$ready_status"
export FAKE_INITIAL_STATUS FAKE_POST_LOGIN_STATUS
: >"$FAKE_LOG"
rm -f "$FAKE_LOGIN_STATE"
WORK_MACHINE=1 "$SCRIPT" >"$TMP/ready.out" 2>"$TMP/ready.err"
[ ! -s "$FAKE_LOG" ] || fail "valid auth was not a no-op"
assert_contains "$TMP/ready.out" 'already valid'

: >"$FAKE_LOG"
if GOOGLE_WORKSPACE_CLI_TOKEN='external-token' WORK_MACHINE=1 "$SCRIPT" >"$TMP/token.out" 2>"$TMP/token.err"; then
    fail "access-token override was accepted"
fi
assert_contains "$TMP/token.err" 'Unset GOOGLE_WORKSPACE_CLI_TOKEN'
[ ! -s "$FAKE_LOG" ] || fail "access-token override reached gws"

: >"$FAKE_LOG"
if GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE='/tmp/external.json' WORK_MACHINE=1 "$SCRIPT" >"$TMP/credentials.out" 2>"$TMP/credentials.err"; then
    fail "external credentials file was accepted"
fi
assert_contains "$TMP/credentials.err" 'GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE'
[ ! -s "$FAKE_LOG" ] || fail "external credentials override reached gws"

FAKE_INITIAL_STATUS='{"user":"yanxi.chen@vanta.com","scopes":[]}'
export FAKE_INITIAL_STATUS
: >"$FAKE_LOG"
rm -f "$FAKE_LOGIN_STATE"
WORK_MACHINE=1 "$SCRIPT" >"$TMP/login.out" 2>"$TMP/login.err"
assert_contains "$FAKE_LOG" 'logout'
assert_contains "$FAKE_LOG" "login <--scopes> <$required_scopes>"
assert_excludes "$FAKE_LOG" 'cloud-platform'

FAKE_INITIAL_STATUS='{"token_valid":true,"user":"yanxi.chen@vanta.com","scopes":["https://www.googleapis.com/auth/documents","https://www.googleapis.com/auth/spreadsheets","https://www.googleapis.com/auth/presentations","https://www.googleapis.com/auth/drive","https://www.googleapis.com/auth/gmail.modify"]}'
export FAKE_INITIAL_STATUS
: >"$FAKE_LOG"
rm -f "$FAKE_LOGIN_STATE"
WORK_MACHINE=1 "$SCRIPT" >"$TMP/extra-scope.out" 2>"$TMP/extra-scope.err"
assert_contains "$FAKE_LOG" 'logout'
assert_contains "$FAKE_LOG" "login <--scopes> <$required_scopes>"

FAKE_INITIAL_STATUS='{"token_valid":true,"user":"someone@gmail.com","scopes":["https://www.googleapis.com/auth/documents","https://www.googleapis.com/auth/spreadsheets","https://www.googleapis.com/auth/presentations","https://www.googleapis.com/auth/drive"]}'
export FAKE_INITIAL_STATUS
: >"$FAKE_LOG"
rm -f "$FAKE_LOGIN_STATE"
if WORK_MACHINE=1 "$SCRIPT" >"$TMP/wrong.out" 2>"$TMP/wrong.err"; then
    fail "non-work Google account was accepted"
fi
assert_contains "$FAKE_LOG" 'logout'
assert_excludes "$FAKE_LOG" 'login'
assert_contains "$TMP/wrong.err" 'non-vanta.com account'

rm -f "$HOME/.config/gws/client_secret.json" "$FAKE_LOGIN_STATE"
FAKE_INITIAL_STATUS='{}'
export FAKE_INITIAL_STATUS
: >"$FAKE_LOG"
if WORK_MACHINE=1 "$SCRIPT" >"$TMP/missing.out" 2>"$TMP/missing.err"; then
    fail "missing OAuth client was accepted"
fi
assert_contains "$TMP/missing.err" 'No Google Workspace OAuth client is configured'
assert_excludes "$FAKE_LOG" 'login'

: >"$FAKE_LOG"
rm -f "$FAKE_LOGIN_STATE"
GOOGLE_WORKSPACE_CLI_CLIENT_ID='test-client-id' \
GOOGLE_WORKSPACE_CLI_CLIENT_SECRET='test-client-secret' \
WORK_MACHINE=1 "$SCRIPT" >"$TMP/env.out" 2>"$TMP/env.err"
assert_contains "$FAKE_LOG" "login <--scopes> <$required_scopes>"
assert_excludes "$TMP/env.out" 'test-client-secret'
assert_excludes "$TMP/env.err" 'test-client-secret'

if WORK_MACHINE=0 "$SCRIPT" >"$TMP/personal.out" 2>"$TMP/personal.err"; then
    fail "auth helper ran outside a work machine"
fi
assert_contains "$TMP/personal.err" 'only available when WORK_MACHINE=1'

cat >"$TMP/bin/ona" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-} ${2:-}" = "environment list" ]; then
    printf '%s\n' '[{"id":"env-1","status":{"content":{"git":{"cloneUrl":"https://github.com/VantaInc/obsidian.git","branch":"main"}}},"metadata":{"lastStartedAt":"2026-07-16T00:00:00Z"}}]'
    exit 0
fi
if [ "${1:-} ${2:-}" = "environment exec" ]; then
    printf '%s\n' \
        'GH_TOKEN=github-token' \
        'GOOGLE_WORKSPACE_CLI_CLIENT_ID=client-id' \
        'GOOGLE_WORKSPACE_CLI_CLIENT_SECRET=client-secret' \
        'GOOGLE_WORKSPACE_CLI_TOKEN=refresh-token' \
        'GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/tmp/credentials.json'
    exit 0
fi
printf 'unexpected ona invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$TMP/bin/ona"

cat >"$TMP/synced-ona-env" <<'EOF'
export GOOGLE_WORKSPACE_CLI_TOKEN=stale-token
export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/tmp/stale-credentials.json
EOF

OUTPUT_FILE="$TMP/synced-ona-env" REQUIRED_VARS='GH_TOKEN' \
    "$ROOT/sync-ona-env-to-cursor-cloud.sh" >"$TMP/sync.out" 2>"$TMP/sync.err"
assert_contains "$TMP/synced-ona-env" 'GOOGLE_WORKSPACE_CLI_CLIENT_ID='
assert_contains "$TMP/synced-ona-env" 'GOOGLE_WORKSPACE_CLI_CLIENT_SECRET='
assert_excludes "$TMP/synced-ona-env" 'GOOGLE_WORKSPACE_CLI_TOKEN'
assert_excludes "$TMP/synced-ona-env" 'GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE'
