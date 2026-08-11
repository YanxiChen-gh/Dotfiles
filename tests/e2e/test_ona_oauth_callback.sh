#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BRIDGE="$ROOT/shared-skills/ona-oauth-callback/bridge.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-ona-oauth-callback-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/state"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    grep -qF "$2" "$1" || fail "$1 does not contain $2"
}

cat >"$TMP/bin/ss" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
    *":$FAKE_CALLBACK_PORT"*)
        if [ "${FAKE_CALLBACK_ALL:-}" = true ]; then
            printf 'LISTEN 0 0 0.0.0.0:%s 0.0.0.0:*\n' "$FAKE_CALLBACK_PORT"
        else
            printf 'LISTEN 0 0 127.0.0.1:%s 0.0.0.0:*\n' "$FAKE_CALLBACK_PORT"
        fi
        ;;
    *":$FAKE_REMOTE_PORT"*)
        [ -f "$FAKE_LISTENER_STATE" ] \
            && printf 'LISTEN 0 0 0.0.0.0:%s 0.0.0.0:*\n' "$FAKE_REMOTE_PORT"
        ;;
esac
EOF

cat >"$TMP/bin/tmux" <<'EOF'
#!/bin/sh
set -eu
command=$1
shift
case "$command" in
    new-session)
        [ "$1" = -d ] && [ "$2" = -s ] || exit 2
        printf '%s\n' "$3" >"$FAKE_SESSION_STATE"
        : >"$FAKE_LISTENER_STATE"
        ;;
    set-environment)
        [ "$1" = -t ] || exit 2
        printf '%s=%s\n' "$3" "$4" >"$FAKE_MARKER_STATE"
        ;;
    has-session)
        [ -f "$FAKE_SESSION_STATE" ]
        ;;
    show-environment)
        cat "$FAKE_MARKER_STATE"
        ;;
    kill-session)
        [ "${FAKE_TMUX_KILL_FAIL:-}" != true ] || exit 1
        rm -f "$FAKE_SESSION_STATE" "$FAKE_MARKER_STATE" "$FAKE_LISTENER_STATE"
        ;;
    *) exit 2 ;;
esac
EOF

cat >"$TMP/bin/socat" <<'EOF'
#!/bin/sh
exit 99
EOF

cat >"$TMP/bin/ona" <<'EOF'
#!/bin/sh
set -eu
case "${1:-} ${2:-} ${3:-}" in
    "environment port get")
        [ -f "$FAKE_REGISTRATION_STATE" ] || exit 1
        [ "${FAKE_REGISTRATION_UNKNOWN:-}" != true ] || exit 1
        cat "$FAKE_REGISTRATION_STATE"
        ;;
    "environment port list")
        if [ -f "$FAKE_REGISTRATION_STATE" ]; then
            printf '[{"port":%s}]\n' "$FAKE_REMOTE_PORT"
        else
            printf '[]\n'
        fi
        ;;
    "environment port open")
        [ "${FAKE_OPEN_FAIL:-}" != true ] || exit 1
        shift 3
        name=
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --name) name=$2; shift 2 ;;
                *) shift ;;
            esac
        done
        printf '%s\n' "$name" >"$FAKE_REGISTRATION_STATE"
        printf 'open %s\n' "$*" >>"$FAKE_ONA_LOG"
        ;;
    "environment port close")
        printf 'close\n' >>"$FAKE_ONA_LOG"
        rm -f "$FAKE_REGISTRATION_STATE"
        ;;
    *)
        printf 'unexpected ona invocation: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF

chmod +x "$TMP/bin/ss" "$TMP/bin/tmux" "$TMP/bin/socat" "$TMP/bin/ona"

FAKE_CALLBACK_PORT=41001
FAKE_REMOTE_PORT=41002
FAKE_LISTENER_STATE="$TMP/listener"
FAKE_SESSION_STATE="$TMP/session"
FAKE_MARKER_STATE="$TMP/marker"
FAKE_REGISTRATION_STATE="$TMP/registration"
FAKE_ONA_LOG="$TMP/ona.log"
export FAKE_CALLBACK_PORT FAKE_REMOTE_PORT FAKE_LISTENER_STATE FAKE_SESSION_STATE
export FAKE_MARKER_STATE FAKE_REGISTRATION_STATE FAKE_ONA_LOG

bridge() {
    ONA_OAUTH_CALLBACK_ONA="$TMP/bin/ona" \
    ONA_OAUTH_CALLBACK_TMUX="$TMP/bin/tmux" \
    ONA_OAUTH_CALLBACK_SS="$TMP/bin/ss" \
    ONA_OAUTH_CALLBACK_SOCAT="$TMP/bin/socat" \
    ONA_OAUTH_CALLBACK_STATE_DIR="$TMP/state" \
    "$BRIDGE" "$@"
}

bridge start --callback-port "$FAKE_CALLBACK_PORT" --remote-port "$FAKE_REMOTE_PORT" \
    --environment-id env-123 >"$TMP/start.out"
assert_contains "$TMP/start.out" \
    "ona environment port forward $FAKE_REMOTE_PORT --environment-id env-123 --local-port $FAKE_CALLBACK_PORT"
assert_contains "$FAKE_ONA_LOG" 'open'

bridge status --remote-port "$FAKE_REMOTE_PORT" >"$TMP/status.out"
assert_contains "$TMP/status.out" 'Managed tmux session: owned'
assert_contains "$TMP/status.out" 'Ona registration: owned'

state_file="$TMP/state/ona-oauth-callback-$FAKE_REMOTE_PORT.state"
registration_name=$(grep '^registration_name=' "$state_file" | cut -d= -f2-)
printf '%s\n' replacement >"$FAKE_REGISTRATION_STATE"
if bridge stop --callback-port "$FAKE_CALLBACK_PORT" --remote-port "$FAKE_REMOTE_PORT" \
        --environment-id env-123 >"$TMP/replaced.out" 2>"$TMP/replaced.err"; then
    fail "cleanup closed a replaced registration"
fi
assert_contains "$TMP/replaced.err" 'refusing to close an unowned'
[ -f "$state_file" ] || fail "partial cleanup removed ownership state"
[ ! -f "$FAKE_SESSION_STATE" ] || fail "partial cleanup left the owned tmux session"

printf '%s\n' "$registration_name" >"$FAKE_REGISTRATION_STATE"
bridge stop --callback-port "$FAKE_CALLBACK_PORT" --remote-port "$FAKE_REMOTE_PORT" \
    --environment-id env-123 >"$TMP/stop.out"
[ ! -e "$state_file" ] || fail "successful cleanup left ownership state"
[ ! -e "$FAKE_REGISTRATION_STATE" ] || fail "successful cleanup left registration"

if bridge status --remote-port "$FAKE_REMOTE_PORT" >"$TMP/absent.out" 2>"$TMP/absent.err"; then
    fail "status adopted absent ownership state"
fi
assert_contains "$TMP/absent.err" 'owned state is absent'

FAKE_REGISTRATION_UNKNOWN=true
export FAKE_REGISTRATION_UNKNOWN
if bridge start --callback-port "$FAKE_CALLBACK_PORT" --remote-port "$FAKE_REMOTE_PORT" \
        --environment-id env-123 >"$TMP/unknown.out" 2>"$TMP/unknown.err"; then
    fail "unverifiable registration was accepted"
fi
[ -f "$state_file" ] || fail "partial start rollback removed ownership state"
assert_contains "$TMP/unknown.err" 'start rollback was partial'
unset FAKE_REGISTRATION_UNKNOWN
bridge stop --callback-port "$FAKE_CALLBACK_PORT" --remote-port "$FAKE_REMOTE_PORT" \
    --environment-id env-123 >/dev/null

FAKE_OPEN_FAIL=true
FAKE_TMUX_KILL_FAIL=true
export FAKE_OPEN_FAIL FAKE_TMUX_KILL_FAIL
if bridge start --callback-port "$FAKE_CALLBACK_PORT" --remote-port "$FAKE_REMOTE_PORT" \
        --environment-id env-123 >"$TMP/kill-fail.out" 2>"$TMP/kill-fail.err"; then
    fail "failed registration open was accepted"
fi
[ -f "$state_file" ] || fail "failed bridge cleanup removed ownership state"
assert_contains "$TMP/kill-fail.err" 'start rollback was partial'
unset FAKE_OPEN_FAIL FAKE_TMUX_KILL_FAIL
bridge stop --callback-port "$FAKE_CALLBACK_PORT" --remote-port "$FAKE_REMOTE_PORT" \
    --environment-id env-123 >/dev/null

FAKE_CALLBACK_ALL=true
export FAKE_CALLBACK_ALL
if bridge start --callback-port "$FAKE_CALLBACK_PORT" --remote-port "$FAKE_REMOTE_PORT" \
        --environment-id env-123 >"$TMP/all.out" 2>"$TMP/all.err"; then
    fail "all-interface OAuth callback was accepted"
fi
assert_contains "$TMP/all.err" 'exactly 127.0.0.1'
