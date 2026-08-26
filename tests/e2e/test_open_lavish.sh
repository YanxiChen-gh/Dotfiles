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
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${LAVISH_AXI_ALLOWED_HOSTS:-}" \
    "${LAVISH_AXI_HOST:-}" \
    "${LAVISH_AXI_LINK_HOST:-}" \
    "${LAVISH_AXI_NO_OPEN:-}" \
    "${LAVISH_AXI_PORT:-}" \
    "${LAVISH_AXI_STATE_DIR:-}" \
    "$*" >>"$FAKE_NPX_LOG"
printf '%s\n' configured >"$FAKE_SERVER_STATE"
printf '%s\n' 'session:' \
    '  file: /tmp/plan.html' \
    "  url: \"http://127.0.0.1:${LAVISH_AXI_PORT:-4387}/session/0123456789abcdef?no-gate=1\"" \
    '  status: opened' \
    'next_step: "Run `lavish-axi poll /tmp/plan.html`."'
EOF

cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
set -eu
output_file=
while [ "$#" -gt 0 ]; do
    case "$1" in
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
else
    printf '%s' '{"ok":true,"app":"lavish-axi"}' >"$output_file"
fi
printf '%s' 200
EOF

cat >"$TMP/fake-expose" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$1" "$2" >>"$FAKE_EXPOSE_LOG"
printf 'http://127.0.0.1:%s%s\n' "$1" "$2"
EOF

chmod +x "$TMP/bin/npx" "$TMP/bin/curl" "$TMP/fake-expose"
PATH="$TMP/bin:$PATH"
FAKE_NPX_LOG="$TMP/npx.log"
FAKE_EXPOSE_LOG="$TMP/expose.log"
FAKE_SERVER_STATE="$TMP/server.state"
export PATH FAKE_NPX_LOG FAKE_EXPOSE_LOG FAKE_SERVER_STATE

run_open() {
    IS_ON_ONA=true \
        LAVISH_AXI_ALLOWED_HOSTS=stale-tailnet.example \
        LAVISH_AXI_PORT=4387 \
        LAVISH_AXI_STATE_DIR="$TMP/shared-state" \
        OPEN_LAVISH_LOCK_FILE="$TMP/lavish.lock" \
        OPEN_LAVISH_EXPOSE_SCRIPT="$TMP/fake-expose" \
        "$SCRIPT" /tmp/plan.html
}

: >"$FAKE_NPX_LOG"
: >"$FAKE_EXPOSE_LOG"
printf '%s\n' absent >"$FAKE_SERVER_STATE"
output=$(run_open 2>"$TMP/fresh.err")
[ "$output" = 'http://127.0.0.1:4387/session/0123456789abcdef?no-gate=1' ] || fail "fresh URL mismatch: $output"
grep -q "$(printf '^\t127.0.0.1\t127.0.0.1\t1\t4387\t%s\t/tmp/plan.html$' "$TMP/shared-state")" "$FAKE_NPX_LOG" || fail "fresh start did not use loopback-only settings"
[ "$(cat "$FAKE_EXPOSE_LOG")" = '4387 /session/0123456789abcdef?no-gate=1' ] || fail "session path was not delegated"
grep -q 'lavish-axi-safe poll /tmp/plan.html' "$TMP/fresh.err" || fail "open guidance did not preserve the safe follow-up command"

: >"$FAKE_NPX_LOG"
run_open >/dev/null 2>"$TMP/reuse.err"
grep -q "$(printf '^\t127.0.0.1\t127.0.0.1\t1\t4387\t%s\t/tmp/plan.html$' "$TMP/shared-state")" "$FAKE_NPX_LOG" || fail "configured server was not reused with loopback settings"

: >"$FAKE_NPX_LOG"
printf '%s\n' foreign >"$FAKE_SERVER_STATE"
if run_open >"$TMP/foreign.out" 2>"$TMP/foreign.err"; then
    fail "foreign port owner should fail closed"
fi
[ ! -s "$FAKE_NPX_LOG" ] || fail "foreign service was mutated"
grep -q 'not a healthy Lavish server' "$TMP/foreign.err" || fail "foreign owner diagnostic missing"

: >"$FAKE_NPX_LOG"
printf '%s\n' absent >"$FAKE_SERVER_STATE"
output=$(IS_ON_ONA='' LAVISH_AXI_PORT=4387 LAVISH_AXI_STATE_DIR="$TMP/shared-state" OPEN_LAVISH_EXPOSE_SCRIPT="$TMP/fake-expose" "$SCRIPT" /tmp/plan.html 2>"$TMP/local.err")
[ "$output" = 'http://127.0.0.1:4387/session/0123456789abcdef?no-gate=1' ] || fail "local URL mismatch"
grep -q "$(printf '^\t\t\t\t4387\t%s\t/tmp/plan.html$' "$TMP/shared-state")" "$FAKE_NPX_LOG" || fail "local opening set remote loopback environment"
mkdir -p "$TMP/worktree-a/.lavish" "$TMP/worktree-b/.lavish"
: >"$TMP/worktree-a/.lavish/review.html"
: >"$TMP/worktree-b/.lavish/review.html"

cat >"$TMP/bin/git" <<EOF
#!/bin/sh
if [ "\$1" = -C ]; then
    case "\$2" in
        "$TMP/worktree-a"/*) printf '%s\n' "$TMP/worktree-a" ;;
        "$TMP/worktree-b"/*) printf '%s\n' "$TMP/worktree-b" ;;
        *) exit 1 ;;
    esac
fi
EOF
chmod +x "$TMP/bin/git"

open_worktree_artifact() {
    HOME="$TMP/home" \
        IS_ON_ONA=true \
        OPEN_LAVISH_EXPOSE_SCRIPT="$TMP/fake-expose" \
        "$SCRIPT" "$1"
}

: >"$FAKE_NPX_LOG"
printf '%s\n' absent >"$FAKE_SERVER_STATE"
open_worktree_artifact "$TMP/worktree-a/.lavish/review.html" >/dev/null
open_worktree_artifact "$TMP/worktree-b/.lavish/review.html" >/dev/null
worktree_a_identity=$(sed -n '1p' "$FAKE_NPX_LOG")
worktree_b_identity=$(sed -n '2p' "$FAKE_NPX_LOG")
worktree_a_config=$(printf '%s\n' "$worktree_a_identity" | cut -f1-6)
worktree_b_config=$(printf '%s\n' "$worktree_b_identity" | cut -f1-6)
[ "$worktree_a_config" != "$worktree_b_config" ] || fail "worktrees shared a Lavish identity"
worktree_a_port=$(printf '%s\n' "$worktree_a_identity" | cut -f5)
worktree_b_port=$(printf '%s\n' "$worktree_b_identity" | cut -f5)
[ "$worktree_a_port" != "$worktree_b_port" ] || fail "worktrees shared a Lavish port"
case "$worktree_a_identity" in
    *"$TMP/home/.lavish-axi/worktrees/"*) ;;
    *) fail "worktree A did not use isolated Lavish state" ;;
esac
case "$worktree_b_identity" in
    *"$TMP/home/.lavish-axi/worktrees/"*) ;;
    *) fail "worktree B did not use isolated Lavish state" ;;
esac


: >"$FAKE_NPX_LOG"
HOME="$TMP/home" IS_ON_ONA=true "$SAFE_SCRIPT" poll "$TMP/worktree-a/.lavish/review.html" >/dev/null
poll_config=$(cut -f1-6 "$FAKE_NPX_LOG")
[ "$poll_config" = "$worktree_a_config" ] || fail "poll did not reuse the worktree Lavish identity"

: >"$FAKE_NPX_LOG"
HOME="$TMP/home" IS_ON_ONA=true "$SAFE_SCRIPT" end "$TMP/worktree-a/.lavish/review.html" >/dev/null
end_config=$(cut -f1-6 "$FAKE_NPX_LOG")
[ "$end_config" = "$worktree_a_config" ] || fail "end did not reuse the worktree Lavish identity"

: >"$FAKE_NPX_LOG"
IS_ON_ONA=true LAVISH_AXI_PORT=48000 LAVISH_AXI_STATE_DIR="$TMP/shared-state" \
    "$SAFE_SCRIPT" poll "$TMP/worktree-a/.lavish/review.html" >/dev/null
grep -q "$(printf '^\t127.0.0.1\t127.0.0.1\t1\t48000\t%s\tpoll %s$' "$TMP/shared-state" "$TMP/worktree-a/.lavish/review.html")" "$FAKE_NPX_LOG" ||
    fail "explicit Lavish identity was not preserved"

: >"$FAKE_NPX_LOG"
IS_ON_ONA=true LAVISH_AXI_PORT=48001 "$SAFE_SCRIPT" poll "$TMP/worktree-a/.lavish/review.html" >/dev/null
grep -q "$(printf '^\t127.0.0.1\t127.0.0.1\t1\t48001\t\tpoll %s$' "$TMP/worktree-a/.lavish/review.html")" "$FAKE_NPX_LOG" ||
    fail "explicit Lavish port was not preserved"

: >"$FAKE_NPX_LOG"
IS_ON_ONA=true LAVISH_AXI_STATE_DIR="$TMP/shared-state-only" "$SAFE_SCRIPT" poll "$TMP/worktree-a/.lavish/review.html" >/dev/null
grep -q "$(printf '^\t127.0.0.1\t127.0.0.1\t1\t\t%s\tpoll %s$' "$TMP/shared-state-only" "$TMP/worktree-a/.lavish/review.html")" "$FAKE_NPX_LOG" ||
    fail "explicit Lavish state directory was not preserved"

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
IS_ON_ONA=true LAVISH_AXI_ALLOWED_HOSTS=stale-tailnet.example LAVISH_AXI_PORT=4387 LAVISH_AXI_STATE_DIR="$TMP/shared-state" "$SAFE_SCRIPT" poll /tmp/plan.html >/dev/null
grep -q "$(printf '^\t127.0.0.1\t127.0.0.1\t1\t4387\t%s\tpoll /tmp/plan.html$' "$TMP/shared-state")" "$FAKE_NPX_LOG" || fail "safe follow-up did not use loopback-only settings"

printf '%s\n' 'open-lavish e2e passed.'
