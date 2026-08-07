#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/expose-port.sh"
TAILSCALE_SCRIPT="$ROOT/scripts/expose-port-tailscale.sh"
PREPARE_SCRIPT="$ROOT/scripts/prepare-ona-tailnet.sh"
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

cat >"$TMP/bin/just" <<'EOF'
#!/bin/sh
: >"$FAKE_JUST_CALLED"
exit 99
EOF

cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
output_file=
write_format=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            output_file=$2
            shift 2
            ;;
        -w)
            write_format=$2
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
if [ -n "$output_file" ] && [ "$output_file" != /dev/null ]; then
    if [ -n "${FAKE_CURL_BODY_FILE:-}" ]; then
        cp "$FAKE_CURL_BODY_FILE" "$output_file"
    else
        printf '%s' "${FAKE_CURL_BODY:-}" >"$output_file"
    fi
fi
case "$write_format" in
    *content_type*) printf '%s\n%s' "${FAKE_CURL_STATUS:-204}" "${FAKE_CURL_CONTENT_TYPE:-application/json}" ;;
    *) printf '%s' "${FAKE_CURL_STATUS:-204}" ;;
esac
EOF

cat >"$TMP/fake-tailscale" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$TAILSCALE_ARGS_FILE"
printf '%s\n' "http://test-node.example:8080${2}"
EOF

chmod +x "$TMP/bin/uname" "$TMP/bin/just" "$TMP/bin/curl" "$TMP/fake-tailscale"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

PATH="$TMP/bin:$PATH"
FAKE_JUST_CALLED="$TMP/just.called"
export FAKE_JUST_CALLED
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
    "$SCRIPT" 8080 /health 2>"$TMP/cde.err")
[ "$output" = "http://test-node.example:8080/health" ] || fail "Ona URL mismatch: $output"
[ "$(cat "$TAILSCALE_ARGS_FILE")" = "8080 /health" ] || fail "Ona delegation arguments mismatch"
[ ! -e "$FAKE_JUST_CALLED" ] || fail "generic exposure invoked a Vanta just recipe"

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
        if [ "${FAKE_JOIN_REQUIRED:-}" = true ] && [ ! -e "$FAKE_JOIN_DONE" ]; then
            exit 1
        fi
        exit 0
        ;;
    up\ *)
        printf '%s\n' "$*" >"$FAKE_TAILSCALE_UP_ARGS"
        printf '%s\n' up >>"$FAKE_TAILSCALE_UP_ACTIONS"
        sleep "${FAKE_UP_DELAY:-0}"
        : >"$FAKE_JOIN_DONE"
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
        if [ "${FAKE_FOREGROUND_HANDLER:-}" = true ]; then
            target=
            if [ -s "$FAKE_SERVE_STATE" ]; then
                IFS= read -r target <"$FAKE_SERVE_STATE"
            fi
            if [ -n "$target" ]; then
                jq -n --arg target "$target" '{
                    TCP:{"8080":{HTTP:true}},
                    Web:{"test-node.example:8080":{Handlers:{"/":{Proxy:$target}}}},
                    Foreground:{"session-1":{
                        TCP:{"8080":{HTTP:true}},
                        Web:{"test-node.example:8080":{Handlers:{"/":{Proxy:"http://localhost:9999"}}}}
                    }}
                }'
            else
                printf '%s\n' '{"TCP":{},"Web":{},"Foreground":{"session-1":{"TCP":{"8080":{"HTTP":true}},"Web":{"test-node.example:8080":{"Handlers":{"/":{"Proxy":"http://localhost:9999"}}}}}}}'
            fi
            exit 0
        fi
        target=
        if [ -s "$FAKE_SERVE_STATE" ]; then
            IFS= read -r target <"$FAKE_SERVE_STATE"
        fi
        if [ -n "$target" ]; then
            if [ "${FAKE_EXTRA_HANDLER:-}" = true ]; then
                jq -n --arg target "$target" '{TCP:{"8080":{HTTP:true}},Web:{"test-node.example:8080":{Handlers:{"/":{Proxy:$target},"/other":{Proxy:"http://localhost:9999"}}}}}'
            else
                jq -n --arg target "$target" '{TCP:{"8080":{HTTP:true}},Web:{"test-node.example:8080":{Handlers:{"/":{Proxy:$target}}}}}'
            fi
        else
            if [ "${FAKE_EXTRA_HANDLER:-}" = true ]; then
                printf '%s\n' '{"TCP":{"8080":{"HTTP":true}},"Web":{"test-node.example:8080":{"Handlers":{"/other":{"Proxy":"http://localhost:9999"}}}}}'
            else
                printf '%s\n' '{"TCP":{},"Web":{}}'
            fi
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
output_file=
write_format=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            output_file=$2
            shift 2
            ;;
        -w)
            write_format=$2
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
if [ -n "$output_file" ] && [ "$output_file" != /dev/null ]; then
    if [ -n "${FAKE_CURL_BODY_FILE:-}" ]; then
        cp "$FAKE_CURL_BODY_FILE" "$output_file"
    else
        printf '%s' "${FAKE_CURL_BODY:-}" >"$output_file"
    fi
fi
if [ -n "${FAKE_CURL_REPLACE_TARGET:-}" ]; then
    printf '%s\n' "$FAKE_CURL_REPLACE_TARGET" >"$FAKE_SERVE_STATE"
fi
case "$write_format" in
    *content_type*) printf '%s\n%s' "${FAKE_CURL_STATUS:-204}" "${FAKE_CURL_CONTENT_TYPE:-application/json}" ;;
    *) printf '%s' "${FAKE_CURL_STATUS:-204}" ;;
esac
EOF

cat >"$TMP/bin/ona" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$FAKE_ONA_ARGS"
printf '%s' "${FAKE_ONA_OUTPUT:-env-123}"
EOF

chmod +x "$TMP/bin/pgrep" "$TMP/bin/sudo" "$TMP/bin/tailscale" "$TMP/bin/curl" "$TMP/bin/ona"
FAKE_SERVE_STATE="$TMP/serve.state"
FAKE_SERVE_ACTIONS="$TMP/serve.actions"
FAKE_JOIN_DONE="$TMP/join.done"
FAKE_ONA_ARGS="$TMP/ona.args"
FAKE_TAILSCALE_UP_ARGS="$TMP/tailscale-up.args"
FAKE_TAILSCALE_UP_ACTIONS="$TMP/tailscale-up.actions"
export FAKE_SERVE_STATE FAKE_SERVE_ACTIONS FAKE_JOIN_DONE FAKE_ONA_ARGS FAKE_TAILSCALE_UP_ARGS FAKE_TAILSCALE_UP_ACTIONS

reset_serve() {
    printf '%s\n' "${1:-}" >"$FAKE_SERVE_STATE"
    : >"$FAKE_SERVE_ACTIONS"
}

reset_serve
rm -f "$FAKE_JOIN_DONE"
FAKE_JOIN_REQUIRED=true
export FAKE_JOIN_REQUIRED
output=$(IS_ON_ONA=true ONA_TAILNET_LOCK_FILE="$TMP/tailnet.lock" "$PREPARE_SCRIPT" 2>"$TMP/join.err")
unset FAKE_JOIN_REQUIRED
[ "$output" = "test-node.example" ] || fail "joined hostname mismatch: $output"
[ "$(cat "$FAKE_ONA_ARGS")" = "environment get --context environment --field id" ] || fail "wrong Ona derivation command"
grep -q -- '--hostname=env-123' "$FAKE_TAILSCALE_UP_ARGS" || fail "derived Ona hostname was not passed to tailscale up"
grep -q -- '--advertise-tags=tag:ona-dev' "$FAKE_TAILSCALE_UP_ARGS" || fail "Ona tailnet tag was not passed to tailscale up"

rm -f "$FAKE_JOIN_DONE"
: >"$FAKE_TAILSCALE_UP_ACTIONS"
FAKE_JOIN_REQUIRED=true
FAKE_UP_DELAY=0.1
export FAKE_JOIN_REQUIRED FAKE_UP_DELAY
IS_ON_ONA=true ONA_TAILNET_LOCK_FILE="$TMP/concurrent-tailnet.lock" "$PREPARE_SCRIPT" >"$TMP/concurrent-one.out" 2>"$TMP/concurrent-one.err" &
first_prepare=$!
IS_ON_ONA=true ONA_TAILNET_LOCK_FILE="$TMP/concurrent-tailnet.lock" "$PREPARE_SCRIPT" >"$TMP/concurrent-two.out" 2>"$TMP/concurrent-two.err" &
second_prepare=$!
wait "$first_prepare" "$second_prepare"
unset FAKE_JOIN_REQUIRED FAKE_UP_DELAY
[ "$(wc -l <"$FAKE_TAILSCALE_UP_ACTIONS" | tr -d ' ')" = 1 ] || fail "concurrent preparation joined the tailnet more than once"
[ "$(cat "$TMP/concurrent-one.out")" = test-node.example ] || fail "first concurrent preparation returned the wrong host"
[ "$(cat "$TMP/concurrent-two.out")" = test-node.example ] || fail "second concurrent preparation returned the wrong host"

reset_serve
rm -f "$FAKE_JOIN_DONE"
FAKE_JOIN_REQUIRED=true
FAKE_ONA_OUTPUT='first
second'
export FAKE_JOIN_REQUIRED FAKE_ONA_OUTPUT
if IS_ON_ONA=true ONA_TAILNET_LOCK_FILE="$TMP/tailnet.lock" "$PREPARE_SCRIPT" >"$TMP/join-invalid.out" 2>"$TMP/join-invalid.err"; then
    fail "multiple Ona environment IDs were accepted"
fi
unset FAKE_JOIN_REQUIRED FAKE_ONA_OUTPUT
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "invalid Ona ID changed Serve"
grep -q "expected exactly one non-empty Ona environment ID" "$TMP/join-invalid.err" || fail "invalid Ona ID diagnostic missing"

rm -f "$FAKE_JOIN_DONE"
FAKE_JOIN_REQUIRED=true
FAKE_ONA_OUTPUT='invalid_name'
export FAKE_JOIN_REQUIRED FAKE_ONA_OUTPUT
if IS_ON_ONA=true ONA_TAILNET_LOCK_FILE="$TMP/tailnet.lock" "$PREPARE_SCRIPT" >"$TMP/join-label.out" 2>"$TMP/join-label.err"; then
    fail "invalid Ona DNS label was accepted"
fi
unset FAKE_JOIN_REQUIRED FAKE_ONA_OUTPUT
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "invalid Ona DNS label changed Serve"
grep -q "expected one DNS label" "$TMP/join-label.err" || fail "invalid Ona DNS label diagnostic missing"

cat >"$TMP/fake-prepare" <<'EOF'
#!/bin/sh
printf '%s\n' test-node.example
EOF
chmod +x "$TMP/fake-prepare"
PREPARE_ONA_TAILNET_SCRIPT="$TMP/fake-prepare"
export PREPARE_ONA_TAILNET_SCRIPT

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
FAKE_CURL_STATUS=403
FAKE_CURL_CONTENT_TYPE='application/json'
FAKE_CURL_BODY='{"error":"forbidden host"}'
export FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /forbidden-host >"$TMP/forbidden-host.out" 2>"$TMP/forbidden-host.err"; then
    fail "Lavish forbidden-host response should fail verification"
fi
unset FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY
grep -q "open the artifact with 'open-lavish'" "$TMP/forbidden-host.err" || fail "forbidden-host remedy missing"
[ ! -s "$FAKE_SERVE_STATE" ] || fail "forbidden-host verification left a newly created Serve mapping"

reset_serve
FAKE_CURL_STATUS=200
FAKE_CURL_CONTENT_TYPE='text/html; charset=utf-8'
FAKE_CURL_BODY_FILE="$TMP/curl-body"
printf '%s' '<html><script src="http://127.0.0.1:9000/app.js"></script></html>' >"$FAKE_CURL_BODY_FILE"
export FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /loopback >"$TMP/loopback.out" 2>"$TMP/loopback.err"; then
    fail "loopback HTML asset should fail verification"
fi
unset FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE
[ ! -s "$FAKE_SERVE_STATE" ] || fail "loopback verification left a newly created Serve mapping"
[ "$(cat "$FAKE_SERVE_ACTIONS")" = "set http://localhost:4387
off" ] || fail "loopback verification cleanup actions mismatch"
grep -q 'http://127.0.0.1:9000/app.js' "$TMP/loopback.err" || fail "loopback diagnostic omitted offending URL"

reset_serve
FAKE_CURL_STATUS=200
FAKE_CURL_CONTENT_TYPE='text/html'
FAKE_CURL_BODY_FILE="$TMP/curl-body"
printf '%s' '<script src="http://127.0.0.2:9000/app.js"></script>' >"$FAKE_CURL_BODY_FILE"
export FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /loopback-range >"$TMP/loopback-range.out" 2>"$TMP/loopback-range.err"; then
    fail "IPv4 loopback-range HTML asset should fail verification"
fi
unset FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE
[ ! -s "$FAKE_SERVE_STATE" ] || fail "IPv4 loopback-range failure left a new Serve mapping"

reset_serve 'http://localhost:1055'
FAKE_CURL_STATUS=200
FAKE_CURL_CONTENT_TYPE='text/html'
FAKE_CURL_BODY_FILE="$TMP/curl-body"
printf '%s' '<link href="http://localhost:9000/app.css" rel="stylesheet">' >"$FAKE_CURL_BODY_FILE"
export FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 1055 /same-loopback >"$TMP/same-loopback.out" 2>"$TMP/same-loopback.err"; then
    fail "loopback HTML asset on unchanged mapping should fail verification"
fi
unset FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE
[ "$(cat "$FAKE_SERVE_STATE")" = 'http://localhost:1055' ] || fail "unchanged mapping was cleaned up after validation failure"
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "unchanged mapping was mutated after validation failure"

reset_serve
FAKE_CURL_STATUS=200
FAKE_CURL_CONTENT_TYPE='application/json'
FAKE_CURL_BODY_FILE="$TMP/curl-body"
printf '%s' '{"example":"<script src=\"http://localhost:9000/app.js\"></script>"}' >"$FAKE_CURL_BODY_FILE"
export FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE
output=$(IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /json 2>"$TMP/json.err")
unset FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE
[ "$output" = "http://test-node.example:8080/json" ] || fail "non-HTML endpoint was rejected"

reset_serve
FAKE_EXTRA_HANDLER=true
export FAKE_EXTRA_HANDLER
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /mixed >"$TMP/mixed.out" 2>"$TMP/mixed.err"; then
    fail "unrelated Serve handler should block mutation"
fi
unset FAKE_EXTRA_HANDLER
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "mixed-handler mapping was mutated"
grep -q 'unrelated Serve handlers' "$TMP/mixed.err" || fail "mixed-handler diagnostic missing"

reset_serve
FAKE_FOREGROUND_HANDLER=true
export FAKE_FOREGROUND_HANDLER
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /foreground >"$TMP/foreground.out" 2>"$TMP/foreground.err"; then
    fail "foreground Serve handler should block mutation"
fi
unset FAKE_FOREGROUND_HANDLER
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "foreground mapping was mutated"
grep -q 'unrelated Serve handlers' "$TMP/foreground.err" || fail "foreground-handler diagnostic missing"

reset_serve 'http://localhost:4387'
FAKE_FOREGROUND_HANDLER=true
export FAKE_FOREGROUND_HANDLER
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /foreground >"$TMP/foreground-combined.out" 2>"$TMP/foreground-combined.err"; then
    fail "foreground handler should override and invalidate a matching background mapping"
fi
unset FAKE_FOREGROUND_HANDLER
[ ! -s "$FAKE_SERVE_ACTIONS" ] || fail "combined foreground mapping was mutated"
grep -q 'unrelated Serve handlers' "$TMP/foreground-combined.err" || fail "combined foreground-handler diagnostic missing"

reset_serve
FAKE_CURL_STATUS=200
FAKE_CURL_CONTENT_TYPE='text/html'
FAKE_CURL_BODY_FILE="$TMP/curl-body"
FAKE_CURL_REPLACE_TARGET='http://localhost:7777'
printf '%s' '<script src="http://localhost:9000/app.js"></script>' >"$FAKE_CURL_BODY_FILE"
export FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE FAKE_CURL_REPLACE_TARGET
if IS_ON_ONA=true "$TAILSCALE_SCRIPT" 4387 /ownership-race >"$TMP/ownership-race.out" 2>"$TMP/ownership-race.err"; then
    fail "loopback HTML asset should fail during ownership-race test"
fi
unset FAKE_CURL_STATUS FAKE_CURL_CONTENT_TYPE FAKE_CURL_BODY_FILE FAKE_CURL_REPLACE_TARGET
[ "$(cat "$FAKE_SERVE_STATE")" = 'http://localhost:7777' ] || fail "cleanup removed a mapping replaced by another process"
[ "$(cat "$FAKE_SERVE_ACTIONS")" = 'set http://localhost:4387' ] || fail "cleanup mutated a mapping replaced by another process"
grep -q 'no longer exclusively owned' "$TMP/ownership-race.err" || fail "ownership-race cleanup diagnostic missing"

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
