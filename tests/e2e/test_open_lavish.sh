#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/open-lavish.sh"
SAFE_SCRIPT="$ROOT/scripts/lavish-axi-safe.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-open-lavish-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

cat >"$TMP/bin/npx" <<'EOF'
#!/bin/sh
set -eu
shift 2
printf '%s\t%s\n' "${LAVISH_AXI_ALLOWED_HOSTS:-}" "$*" >>"$FAKE_NPX_LOG"
if [ "${1:-}" = stop ]; then
    printf '%s\n' absent >"$FAKE_SERVER_STATE"
    printf '%s\n' 'server: stopped'
    exit 0
fi
printf '%s\n' configured >"$FAKE_SERVER_STATE"
printf '%s\n' 'session:' \
    '  file: /tmp/plan.html' \
    '  url: "http://127.0.0.1:4387/session/0123456789abcdef?no-gate=1"' \
    '  status: opened' \
    'next_step: "Run `lavish-axi poll /tmp/plan.html`."'
EOF

cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
set -eu
host=
output_file=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -H) host=${2#Host: }; shift 2 ;;
        -o) output_file=$2; shift 2 ;;
        -w) shift 2 ;;
        *) shift ;;
    esac
done
state=$(cat "$FAKE_SERVER_STATE")
if [ "$state" = absent ]; then
    exit 7
fi
if [ "$state" = foreign ]; then
    printf '%s' '{"ok":true,"app":"other"}' >"$output_file"
    printf '%s' 200
    exit 0
fi
case "$host" in
    127.0.0.1:*)
        printf '%s' '{"ok":true,"app":"lavish-axi"}' >"$output_file"
        printf '%s' 200
        ;;
    *)
        if [ "$state" = misconfigured ]; then
            printf '%s' '{"error":"forbidden host"}' >"$output_file"
            printf '%s' 403
        else
            printf '%s' '{"ok":true,"app":"lavish-axi"}' >"$output_file"
            printf '%s' 200
        fi
        ;;
esac
EOF

cat >"$TMP/fake-prepare" <<'EOF'
#!/bin/sh
printf '%s\n' called >>"$FAKE_PREPARE_LOG"
printf '%s\n' test-node.example
EOF

cat >"$TMP/fake-expose" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$1" "$2" >>"$FAKE_EXPOSE_LOG"
printf 'http://test-node.example:8080%s\n' "$2"
EOF

chmod +x "$TMP/bin/npx" "$TMP/bin/curl" "$TMP/fake-prepare" "$TMP/fake-expose"
PATH="$TMP/bin:$PATH"
FAKE_NPX_LOG="$TMP/npx.log"
FAKE_PREPARE_LOG="$TMP/prepare.log"
FAKE_EXPOSE_LOG="$TMP/expose.log"
FAKE_SERVER_STATE="$TMP/server.state"
export PATH FAKE_NPX_LOG FAKE_PREPARE_LOG FAKE_EXPOSE_LOG FAKE_SERVER_STATE

run_open() {
    IS_ON_ONA=true \
        OPEN_LAVISH_LOCK_FILE="$TMP/lavish.lock" \
        OPEN_LAVISH_PREPARE_SCRIPT="$TMP/fake-prepare" \
        OPEN_LAVISH_EXPOSE_SCRIPT="$TMP/fake-expose" \
        "$SCRIPT" /tmp/plan.html
}

: >"$FAKE_NPX_LOG"
: >"$FAKE_PREPARE_LOG"
: >"$FAKE_EXPOSE_LOG"
printf '%s\n' absent >"$FAKE_SERVER_STATE"
output=$(run_open 2>"$TMP/fresh.err")
[ "$output" = 'http://test-node.example:8080/session/0123456789abcdef?no-gate=1' ] || fail "fresh URL mismatch: $output"
grep -q "$(printf '^test-node.example\t/tmp/plan.html$')" "$FAKE_NPX_LOG" || fail "fresh start omitted the exact allowed host"
[ "$(cat "$FAKE_EXPOSE_LOG")" = '4387 /session/0123456789abcdef?no-gate=1' ] || fail "session path was not delegated"
grep -q 'lavish-axi-safe poll /tmp/plan.html' "$TMP/fresh.err" || fail "open guidance did not preserve the safe follow-up command"

: >"$FAKE_NPX_LOG"
printf '%s\n' configured >"$FAKE_SERVER_STATE"
run_open >/dev/null 2>"$TMP/reuse.err"
grep -q "$(printf '^test-node.example\t/tmp/plan.html$')" "$FAKE_NPX_LOG" || fail "configured server was not reused"
if grep -q "$(printf '\tstop$')" "$FAKE_NPX_LOG"; then fail "configured server was restarted"; fi

: >"$FAKE_NPX_LOG"
printf '%s\n' misconfigured >"$FAKE_SERVER_STATE"
if ! run_open >/dev/null 2>"$TMP/repair.err"; then
    cat "$TMP/repair.err" >&2
    fail "misconfigured Lavish server was not repaired"
fi
[ "$(sed -n '1p' "$FAKE_NPX_LOG")" = "$(printf '\tstop')" ] || fail "repair did not stop Lavish first"
[ "$(sed -n '2p' "$FAKE_NPX_LOG")" = "$(printf 'test-node.example\t/tmp/plan.html')" ] || fail "repair did not restart with the exact host"
grep -q 'restarting the shared Lavish server' "$TMP/repair.err" || fail "repair was not reported"

: >"$FAKE_NPX_LOG"
printf '%s\n' foreign >"$FAKE_SERVER_STATE"
if run_open >"$TMP/foreign.out" 2>"$TMP/foreign.err"; then
    fail "foreign port owner should fail closed"
fi
[ ! -s "$FAKE_NPX_LOG" ] || fail "foreign service was mutated"
grep -q 'not a healthy Lavish server' "$TMP/foreign.err" || fail "foreign owner diagnostic missing"

: >"$FAKE_NPX_LOG"
: >"$FAKE_PREPARE_LOG"
output=$(IS_ON_ONA='' OPEN_LAVISH_EXPOSE_SCRIPT="$TMP/fake-expose" "$SCRIPT" /tmp/plan.html 2>"$TMP/local.err")
[ "$output" = 'http://test-node.example:8080/session/0123456789abcdef?no-gate=1' ] || fail "local URL mismatch"
[ ! -s "$FAKE_PREPARE_LOG" ] || fail "local opening prepared Ona tailnet"
grep -q "$(printf '^\t/tmp/plan.html$')" "$FAKE_NPX_LOG" || fail "local opening set a tailnet allowed host"

resolve_script_dir() {
    printf '%s\n' "$ROOT"
}
# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/35-agent-helpers.sh
. "$ROOT/install.d/35-agent-helpers.sh"
HOME="$TMP/home"
export HOME
setup_agent_helpers
[ -L "$HOME/.local/bin/open-lavish" ] || fail "installer did not link open-lavish"
[ "$(readlink "$HOME/.local/bin/open-lavish")" = "$SCRIPT" ] || fail "open-lavish link points to the wrong source"
[ -L "$HOME/.local/bin/lavish-axi-safe" ] || fail "installer did not link lavish-axi-safe"
[ "$(readlink "$HOME/.local/bin/lavish-axi-safe")" = "$SAFE_SCRIPT" ] || fail "lavish-axi-safe link points to the wrong source"

: >"$FAKE_NPX_LOG"
IS_ON_ONA=true OPEN_LAVISH_PREPARE_SCRIPT="$TMP/fake-prepare" "$SAFE_SCRIPT" poll /tmp/plan.html >/dev/null
grep -q "$(printf '^test-node.example\tpoll /tmp/plan.html$')" "$FAKE_NPX_LOG" || fail "safe follow-up omitted the exact allowed host"

printf '%s\n' 'open-lavish e2e passed.'
