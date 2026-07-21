#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/expose-port.sh"
TAILSCALE_SCRIPT="$ROOT/scripts/expose-port-tailscale.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-expose-port-$$"
SOCKS_PID=

cleanup() {
    if [ -n "$SOCKS_PID" ]; then
        kill "$SOCKS_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP/bin"

cat >"$TMP/bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_UNAME:-Darwin}"
EOF

cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
printf '%s' "${FAKE_CURL_STATUS:-204}"
EOF

cat >"$TMP/fake-tailscale" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$TAILSCALE_ARGS_FILE"
printf '%s\n' "http://test-node.example:8080${2}"
EOF

chmod +x "$TMP/bin/uname" "$TMP/bin/curl" "$TMP/fake-tailscale"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

PATH="$TMP/bin:$PATH"
export PATH

output=$(IS_ON_ONA='' FAKE_UNAME=Darwin "$SCRIPT" 4387 /session/local 2>"$TMP/local.err")
[ "$output" = "http://127.0.0.1:4387/session/local" ] || fail "local auto URL mismatch: $output"
grep -q 'verified local URL (204)' "$TMP/local.err" || fail "local verification was not reported"

output=$(IS_ON_ONA='' FAKE_UNAME=Linux "$SCRIPT" --local 4387 /session/override 2>"$TMP/override.err")
[ "$output" = "http://127.0.0.1:4387/session/override" ] || fail "local override URL mismatch: $output"

if IS_ON_ONA='' FAKE_UNAME=Linux "$SCRIPT" 4387 /session/remote >"$TMP/remote.out" 2>"$TMP/remote.err"; then
    fail "unknown Linux remote should fail closed"
fi
[ ! -s "$TMP/remote.out" ] || fail "unknown remote wrote stdout"
grep -q 'cannot infer browser reachability' "$TMP/remote.err" || fail "unknown remote error missing"

if IS_ON_ONA='' FAKE_UNAME=Darwin FAKE_CURL_STATUS=500 "$SCRIPT" 4387 /broken >"$TMP/broken.out" 2>"$TMP/broken.err"; then
    fail "failed local verification should fail"
fi
[ ! -s "$TMP/broken.out" ] || fail "failed verification wrote stdout"
grep -q 'local verification failed (500)' "$TMP/broken.err" || fail "failed verification error missing"

TAILSCALE_ARGS_FILE="$TMP/tailscale.args"
export TAILSCALE_ARGS_FILE
output=$(IS_ON_ONA=true EXPOSE_PORT_TAILSCALE_SCRIPT="$TMP/fake-tailscale" \
    "$SCRIPT" 4387 /session/cde 2>"$TMP/cde.err")
[ "$output" = "http://test-node.example:8080/session/cde" ] || fail "Ona URL mismatch: $output"
[ "$(cat "$TAILSCALE_ARGS_FILE")" = "4387 /session/cde" ] || fail "Ona delegation arguments mismatch"

if "$SCRIPT" invalid / >"$TMP/invalid.out" 2>"$TMP/invalid.err"; then
    fail "invalid port should fail"
fi
grep -q 'local port must be an integer' "$TMP/invalid.err" || fail "invalid port error missing"

if "$SCRIPT" --local 4387 no-leading-slash >"$TMP/path.out" 2>"$TMP/path.err"; then
    fail "invalid path should fail"
fi
grep -q "verify path must start with '/'" "$TMP/path.err" || fail "invalid path error missing"

# Exercise the Tailscale implementation with a real local socket and fake CLI.
if ! timeout 1 bash -c 'exec 3<>/dev/tcp/localhost/1055' 2>/dev/null; then
    python3 -c '
import socket

server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 1055))
server.listen()
while True:
    connection, _ = server.accept()
    connection.close()
' >"$TMP/socks.log" 2>&1 &
    SOCKS_PID=$!
    for _ in $(seq 20); do
        timeout 1 bash -c 'exec 3<>/dev/tcp/localhost/1055' 2>/dev/null && break
        sleep 0.1
    done
    timeout 1 bash -c 'exec 3<>/dev/tcp/localhost/1055' 2>/dev/null || fail "test SOCKS socket did not start"
fi

cat >"$TMP/bin/pgrep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$TMP/bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF

cat >"$TMP/bin/tailscale" <<'EOF'
#!/bin/sh
set -eu

case "$*" in
    "status --self --peers=false")
        exit 0
        ;;
    "status --json")
        printf '%s\n' '{"Self":{"DNSName":"test-node.example."}}'
        ;;
    "serve status --json")
        if [ "${FAKE_STATUS_ERROR:-}" = true ]; then
            exit 1
        fi
        if [ "${FAKE_STATUS_INVALID:-}" = true ]; then
            printf '%s\n' invalid
            exit 0
        fi
        target=
        if [ -s "$FAKE_SERVE_STATE" ]; then
            IFS= read -r target <"$FAKE_SERVE_STATE"
        fi
        if [ -n "$target" ]; then
            jq -n --arg target "$target" '{TCP:{"8080":{HTTP:true}},Web:{"test-node.example:8080":{Handlers:{"/":{Proxy:$target}}}}}'
        else
            printf '%s\n' '{"TCP":{},"Web":{}}'
        fi
        ;;
    "serve --http=8080 off")
        : >"$FAKE_SERVE_STATE"
        printf '%s\n' off >>"$FAKE_SERVE_ACTIONS"
        ;;
    serve\ --bg\ --http=8080\ *)
        target=${4}
        printf '%s\n' "$target" >"$FAKE_SERVE_STATE"
        printf 'set %s\n' "$target" >>"$FAKE_SERVE_ACTIONS"
        ;;
    *)
        printf 'unexpected tailscale command: %s\n' "$*" >&2
        exit 1
        ;;
esac
EOF

cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
printf '%s' "${FAKE_CURL_STATUS:-204}"
EOF

chmod +x "$TMP/bin/pgrep" "$TMP/bin/sudo" "$TMP/bin/tailscale" "$TMP/bin/curl"
FAKE_SERVE_STATE="$TMP/serve.state"
FAKE_SERVE_ACTIONS="$TMP/serve.actions"
export FAKE_SERVE_STATE FAKE_SERVE_ACTIONS

reset_serve() {
    printf '%s\n' "${1:-}" >"$FAKE_SERVE_STATE"
    : >"$FAKE_SERVE_ACTIONS"
}

reset_serve 'http://localhost:1055'
output=$(IS_ON_ONA=true "$TAILSCALE_SCRIPT" 1055 /same 2>"$TMP/same.err")
[ "$output" = "http://test-node.example:8080/same" ] || fail "same-target URL mismatch: $output"
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "same target reconfigured Serve"

reset_serve 'http://localhost:1055'
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /conflict >"$TMP/conflict.out" 2>"$TMP/conflict.err"; then
    fail "live conflicting target should fail"
fi
[ ! -s "$TMP/conflict.out" ] || fail "live conflict wrote stdout"
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "live conflict changed Serve"
grep -q 'refusing to break its URL' "$TMP/conflict.err" || fail "live conflict error missing"

reset_serve 'http://localhost:65530'
output=$(IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /stale 2>"$TMP/stale.err")
[ "$output" = "http://test-node.example:8080/stale" ] || fail "stale-target URL mismatch: $output"
[ "$(cat "$FAKE_SERVE_STATE")" = 'http://localhost:4387' ] || fail "stale target was not replaced"
[ "$(cat "$FAKE_SERVE_ACTIONS")" = "off
set http://localhost:4387" ] || fail "stale replacement actions mismatch"

reset_serve
output=$(IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /fresh 2>"$TMP/fresh.err")
[ "$output" = "http://test-node.example:8080/fresh" ] || fail "fresh URL mismatch: $output"
[ "$(cat "$FAKE_SERVE_ACTIONS")" = 'set http://localhost:4387' ] || fail "fresh mapping actions mismatch"

reset_serve
FAKE_CURL_STATUS=500
export FAKE_CURL_STATUS
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /broken >"$TMP/verify.out" 2>"$TMP/verify.err"; then
    fail "failed Tailscale verification should fail"
fi
unset FAKE_CURL_STATUS
[ ! -s "$FAKE_SERVE_STATE" ] || fail "failed verification left a Serve mapping"
[ "$(cat "$FAKE_SERVE_ACTIONS")" = "set http://localhost:4387
off" ] || fail "failed verification cleanup actions mismatch"

reset_serve 'http://localhost:1055'
FAKE_STATUS_ERROR=true
export FAKE_STATUS_ERROR
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /status >"$TMP/status.out" 2>"$TMP/status.err"; then
    fail "unreadable Serve status should fail closed"
fi
unset FAKE_STATUS_ERROR
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "status failure changed Serve"
grep -q 'refusing to replace it' "$TMP/status.err" || fail "status failure error missing"

reset_serve 'http://localhost:1055'
FAKE_STATUS_INVALID=true
export FAKE_STATUS_INVALID
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /status >"$TMP/invalid-status.out" 2>"$TMP/invalid-status.err"; then
    fail "invalid Serve status should fail closed"
fi
unset FAKE_STATUS_INVALID
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "invalid status changed Serve"
grep -q 'status is invalid' "$TMP/invalid-status.err" || fail "invalid status error missing"
