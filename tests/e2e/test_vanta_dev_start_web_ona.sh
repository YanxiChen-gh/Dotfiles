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
printf '%s\n' "$*" >"$FAKE_JUST_ARGS"
printf '%s\n' "${PARCEL_PUBLIC_URL:-}" >"$FAKE_PARCEL_PUBLIC_URL"
EOF

cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
printf '%s' "${FAKE_CURL_STATUS:-204}"
EOF

cat >"$TMP/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$TMP/fake-expose" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$FAKE_EXPOSE_ARGS"
printf '%s\n' 'http://test-node.example:8080/'
EOF

chmod +x "$TMP/bin/just" "$TMP/bin/curl" "$TMP/bin/sleep" "$TMP/fake-expose"

FAKE_JUST_ARGS="$TMP/just.args"
FAKE_PARCEL_PUBLIC_URL="$TMP/parcel-public-url"
FAKE_EXPOSE_ARGS="$TMP/expose.args"
export FAKE_JUST_ARGS FAKE_PARCEL_PUBLIC_URL FAKE_EXPOSE_ARGS

PATH="$TMP/bin:$PATH"
export PATH

output=$(IS_ON_ONA=true EXPOSE_PORT_SCRIPT="$TMP/fake-expose" "$SCRIPT" 2>"$TMP/default.err")
[ "$output" = 'http://test-node.example:8080/' ] || fail "wrapper URL mismatch: $output"
[ "$(cat "$FAKE_JUST_ARGS")" = 'dev-start-web' ] || fail "wrapper used the wrong just recipe"
[ "$(cat "$FAKE_PARCEL_PUBLIC_URL")" = / ] || fail "wrapper did not default PARCEL_PUBLIC_URL"
[ "$(cat "$FAKE_EXPOSE_ARGS")" = '8080 /' ] || fail "wrapper exposed the wrong endpoint"

PARCEL_PUBLIC_URL='https://assets.example.test/custom/' \
    IS_ON_ONA=true EXPOSE_PORT_SCRIPT="$TMP/fake-expose" "$SCRIPT" \
    >"$TMP/override.out" 2>"$TMP/override.err"
[ "$(cat "$FAKE_PARCEL_PUBLIC_URL")" = 'https://assets.example.test/custom/' ] || fail "wrapper replaced an explicit PARCEL_PUBLIC_URL"

if IS_ON_ONA=false EXPOSE_PORT_SCRIPT="$TMP/fake-expose" "$SCRIPT" \
    >"$TMP/non-ona.out" 2>"$TMP/non-ona.err"; then
    fail "wrapper should reject non-Ona environments"
fi
grep -q 'only for an Ona CDE' "$TMP/non-ona.err" || fail "non-Ona diagnostic missing"

FAKE_CURL_STATUS=503
export FAKE_CURL_STATUS
if IS_ON_ONA=true VANTA_DEV_READY_ATTEMPTS=2 EXPOSE_PORT_SCRIPT="$TMP/fake-expose" \
    "$SCRIPT" >"$TMP/timeout.out" 2>"$TMP/timeout.err"; then
    fail "wrapper should fail when nginx never becomes ready"
fi
unset FAKE_CURL_STATUS
grep -q 'nginx did not become ready' "$TMP/timeout.err" || fail "readiness timeout diagnostic missing"

printf '%s\n' 'vanta-dev-start-web-ona tests passed'
