#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/vanta-dev-start-web-ona.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-vanta-start-$$"

cleanup() {
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$TMP/bin"

cat >"$TMP/bin/just" <<'EOF'
#!/bin/sh
printf '%s|%s\n' "${PARCEL_PUBLIC_URL:-}" "$*" >>"$FAKE_JUST_ACTIONS"
if [ "$*" = 'dev-replace web-client' ] && [ -f "${FAKE_REPAIRED_BODY_FILE:-}" ]; then
    cp "$FAKE_REPAIRED_BODY_FILE" "$FAKE_CURL_BODY_FILE"
fi
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
    cp "$FAKE_CURL_BODY_FILE" "$output_file"
fi
case "$write_format" in
    *content_type*) printf '%s\n%s' "${FAKE_CURL_STATUS:-200}" "${FAKE_CURL_CONTENT_TYPE:-text/html}" ;;
    *) printf '%s' "${FAKE_CURL_STATUS:-200}" ;;
esac
EOF

cat >"$TMP/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$TMP/fake-expose" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_EXPOSE_ACTIONS"
printf '%s\n' 'http://test-node.example:8080/'
EOF

chmod +x "$TMP/bin/just" "$TMP/bin/curl" "$TMP/bin/sleep" "$TMP/fake-expose"

FAKE_JUST_ACTIONS="$TMP/just.actions"
FAKE_EXPOSE_ACTIONS="$TMP/expose.actions"
FAKE_CURL_BODY_FILE="$TMP/current.html"
FAKE_REPAIRED_BODY_FILE="$TMP/repaired.html"
export FAKE_JUST_ACTIONS FAKE_EXPOSE_ACTIONS FAKE_CURL_BODY_FILE FAKE_REPAIRED_BODY_FILE

PATH="$TMP/bin:$PATH"
export PATH

reset_case() {
    : >"$FAKE_JUST_ACTIONS"
    : >"$FAKE_EXPOSE_ACTIONS"
    : >"$FAKE_CURL_BODY_FILE"
    rm -f "$FAKE_REPAIRED_BODY_FILE"
}

reset_case
printf '%s\n' '<html><script src="/app.js"></script></html>' >"$FAKE_CURL_BODY_FILE"
output=$(IS_ON_ONA=true EXPOSE_PORT_SCRIPT="$TMP/fake-expose" "$SCRIPT" 2>"$TMP/default.err")
[ "$output" = 'http://test-node.example:8080/' ] || fail "wrapper URL mismatch: $output"
[ "$(cat "$FAKE_JUST_ACTIONS")" = '/|dev-start-web' ] || fail "browser-safe page should not replace web-client"
[ "$(cat "$FAKE_EXPOSE_ACTIONS")" = '8080 /' ] || fail "wrapper exposed the wrong endpoint"

reset_case
printf '%s\n' '<html><script src="/app.js"></script></html>' >"$FAKE_CURL_BODY_FILE"
PARCEL_PUBLIC_URL='https://assets.example.test/custom/' \
    IS_ON_ONA=true EXPOSE_PORT_SCRIPT="$TMP/fake-expose" "$SCRIPT" \
    >"$TMP/override.out" 2>"$TMP/override.err"
[ "$(cat "$FAKE_JUST_ACTIONS")" = 'https://assets.example.test/custom/|dev-start-web' ] \
    || fail "wrapper replaced an explicit PARCEL_PUBLIC_URL"

reset_case
printf '%s\n' '<html><script src="http://127.0.0.1:9000/app.js"></script></html>' >"$FAKE_CURL_BODY_FILE"
printf '%s\n' '<html><script src="/app.js"></script></html>' >"$FAKE_REPAIRED_BODY_FILE"
output=$(IS_ON_ONA=true EXPOSE_PORT_SCRIPT="$TMP/fake-expose" "$SCRIPT" 2>"$TMP/repair.err")
[ "$output" = 'http://test-node.example:8080/' ] || fail "repaired wrapper URL mismatch: $output"
[ "$(cat "$FAKE_JUST_ACTIONS")" = '/|dev-start-web
/|dev-replace web-client' ] || fail "wrapper did not perform exactly one targeted repair"
grep -q 'http://127.0.0.1:9000/app.js' "$TMP/repair.err" || fail "repair diagnostic omitted the offending URL"
[ "$(cat "$FAKE_EXPOSE_ACTIONS")" = '8080 /' ] || fail "repaired page was not exposed"

for loopback_host in localhost 127.0.0.2; do
    reset_case
    printf '<html><link href="http://%s:9000/app.css" rel="stylesheet"></html>\n' "$loopback_host" >"$FAKE_CURL_BODY_FILE"
    printf '%s\n' '<html><link href="/app.css" rel="stylesheet"></html>' >"$FAKE_REPAIRED_BODY_FILE"
    IS_ON_ONA=true EXPOSE_PORT_SCRIPT="$TMP/fake-expose" "$SCRIPT" \
        >"$TMP/${loopback_host}.out" 2>"$TMP/${loopback_host}.err"
    [ "$(cat "$FAKE_JUST_ACTIONS")" = '/|dev-start-web
/|dev-replace web-client' ] || fail "$loopback_host did not trigger exactly one repair"
done

reset_case
printf '%s\n' '<html><script src="http://localhost:9000/app.js"></script></html>' >"$FAKE_CURL_BODY_FILE"
if IS_ON_ONA=true VANTA_DEV_READY_ATTEMPTS=2 EXPOSE_PORT_SCRIPT="$TMP/fake-expose" \
    "$SCRIPT" >"$TMP/unrepaired.out" 2>"$TMP/unrepaired.err"; then
    fail "wrapper should fail when targeted repair leaves a loopback asset"
fi
[ "$(cat "$FAKE_JUST_ACTIONS")" = '/|dev-start-web
/|dev-replace web-client' ] || fail "failed repair should not restart or replace more than once"
[ ! -s "$FAKE_EXPOSE_ACTIONS" ] || fail "unrepaired page should not be exposed"
grep -q 'browser-active asset still uses CDE loopback' "$TMP/unrepaired.err" || fail "failed repair diagnostic missing"

if IS_ON_ONA=false EXPOSE_PORT_SCRIPT="$TMP/fake-expose" "$SCRIPT" \
    >"$TMP/non-ona.out" 2>"$TMP/non-ona.err"; then
    fail "wrapper should reject non-Ona environments"
fi
grep -q 'only for an Ona CDE' "$TMP/non-ona.err" || fail "non-Ona diagnostic missing"

reset_case
FAKE_CURL_STATUS=503
export FAKE_CURL_STATUS
if IS_ON_ONA=true VANTA_DEV_READY_ATTEMPTS=2 EXPOSE_PORT_SCRIPT="$TMP/fake-expose" \
    "$SCRIPT" >"$TMP/timeout.out" 2>"$TMP/timeout.err"; then
    fail "wrapper should fail when nginx never becomes ready"
fi
unset FAKE_CURL_STATUS
grep -q 'root page did not become ready' "$TMP/timeout.err" || fail "readiness timeout diagnostic missing"

printf '%s\n' 'vanta-dev-start-web-ona tests passed'
