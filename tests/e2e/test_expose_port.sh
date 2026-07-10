#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/expose-port.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-expose-port-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

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
