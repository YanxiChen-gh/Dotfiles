#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SETUP="$ROOT/scripts/setup-vanta-data-apps.sh"
CONFIGURE="$ROOT/scripts/configure_vanta_snowflake.py"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-vanta-data-apps-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/home/.snowflake"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    grep -qF "$2" "$1" || fail "$1 does not contain $2"
}

cat >"$TMP/bin/gh" <<'EOF'
#!/bin/sh
set -eu
[ "$1 $2 $3" = "repo clone VantaInc/data-apps" ] || exit 2
target=$4
mkdir -p "$target"
git -C "$target" init -q
git -C "$target" remote add origin https://github.com/VantaInc/data-apps.git
: >"$target/requirements.txt"
printf 'clone\n' >>"$FAKE_GH_LOG"
EOF

cat >"$TMP/bin/python-for-venv" <<'EOF'
#!/bin/sh
set -eu
[ "$1 $2" = "-m venv" ] || exit 2
shift 2
[ "${1:-}" = "--clear" ] && shift
venv=$1
mkdir -p "$venv/bin"
cat >"$venv/bin/python" <<'INNER'
#!/bin/sh
exit 0
INNER
cat >"$venv/bin/pip" <<'INNER'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_PIP_LOG"
INNER
chmod +x "$venv/bin/python" "$venv/bin/pip"
EOF

chmod +x "$TMP/bin/gh" "$TMP/bin/python-for-venv"

cat >"$TMP/home/.snowflake/connections.toml" <<'EOF'
[OTHER]
account = "unrelated"
EOF
cat >"$TMP/home/.snowflake/config.toml" <<'EOF'
[cli]
output_format = "json"
EOF

HOME="$TMP/home"
FAKE_GH_LOG="$TMP/gh.log"
FAKE_PIP_LOG="$TMP/pip.log"
export HOME FAKE_GH_LOG FAKE_PIP_LOG

DATA_APPS_GH="$TMP/bin/gh" \
DATA_APPS_PYTHON="$TMP/bin/python-for-venv" \
SNOWFLAKE_CONFIG_PYTHON=python3 \
"$SETUP" --repo-dir "$TMP/data-apps" --user yanxi.chen@vanta.com >"$TMP/setup.out"

[ "$(wc -l <"$FAKE_GH_LOG" | tr -d ' ')" = 1 ] || fail "repository was not cloned exactly once"
assert_contains "$FAKE_PIP_LOG" "install -r $TMP/data-apps/requirements.txt"
assert_contains "$HOME/.snowflake/connections.toml" '[OTHER]'
assert_contains "$HOME/.snowflake/connections.toml" '[JYFRXUC-VANTA]'
assert_contains "$HOME/.snowflake/connections.toml" 'client_store_temporary_credential = true'
assert_contains "$HOME/.snowflake/config.toml" 'default_connection_name = "JYFRXUC-VANTA"'
assert_contains "$HOME/.snowflake/config.toml" '[cli]'
[ "$(stat -c %a "$HOME/.snowflake/connections.toml")" = 600 ] || fail "connections.toml mode is not 600"
[ "$(stat -c %a "$HOME/.snowflake/config.toml")" = 600 ] || fail "config.toml mode is not 600"
[ "$(stat -c %a "$HOME/.cache/snowflake")" = 700 ] || fail "Snowflake cache mode is not 700"

DATA_APPS_GH="$TMP/bin/gh" \
DATA_APPS_PYTHON="$TMP/bin/python-for-venv" \
SNOWFLAKE_CONFIG_PYTHON=python3 \
"$SETUP" --repo-dir "$TMP/data-apps" --user yanxi.chen@vanta.com >/dev/null
[ "$(wc -l <"$FAKE_GH_LOG" | tr -d ' ')" = 1 ] || fail "idempotent setup cloned again"

git -C "$TMP/data-apps" add requirements.txt
git -C "$TMP/data-apps" -c user.name=Test -c user.email=test@example.com commit -qm initial
git -C "$TMP/data-apps" worktree add -q "$TMP/data-apps-worktree"
DATA_APPS_GH="$TMP/bin/gh" \
DATA_APPS_PYTHON="$TMP/bin/python-for-venv" \
SNOWFLAKE_CONFIG_PYTHON=python3 \
"$SETUP" --repo-dir "$TMP/data-apps-worktree" --user yanxi.chen@vanta.com >/dev/null
[ "$(wc -l <"$FAKE_GH_LOG" | tr -d ' ')" = 1 ] || fail "worktree setup cloned again"

mkdir -p "$TMP/conflict-home/.snowflake"
cat >"$TMP/conflict-home/.snowflake/config.toml" <<'EOF'
default_connection_name = "OTHER"
EOF
cp "$TMP/conflict-home/.snowflake/config.toml" "$TMP/conflict-before.toml"
if HOME="$TMP/conflict-home" python3 "$CONFIGURE" --user yanxi.chen@vanta.com >"$TMP/conflict.out" 2>"$TMP/conflict.err"; then
    fail "conflicting Snowflake default was overwritten"
fi
cmp "$TMP/conflict-home/.snowflake/config.toml" "$TMP/conflict-before.toml" \
    || fail "conflicting Snowflake default changed"
[ ! -e "$TMP/conflict-home/.snowflake/connections.toml" ] \
    || fail "connection profile was written before default conflict validation"
assert_contains "$TMP/conflict.err" 'refusing to replace it'

mkdir -p "$TMP/partial-home/.snowflake"
cat >"$TMP/partial-home/.snowflake/connections.toml" <<'EOF'
[JYFRXUC-VANTA]
account = "JYFRXUC-VANTA"
user = "yanxi.chen@vanta.com"
EOF
HOME="$TMP/partial-home" python3 "$CONFIGURE" --user yanxi.chen@vanta.com >/dev/null
assert_contains "$TMP/partial-home/.snowflake/connections.toml" 'authenticator = "externalbrowser"'
assert_contains "$TMP/partial-home/.snowflake/connections.toml" 'schema = "STREAMLIT_APPS"'

mkdir -p "$TMP/concurrent-home"
HOME="$TMP/concurrent-home" python3 "$CONFIGURE" --user yanxi.chen@vanta.com >/dev/null &
configure_one=$!
HOME="$TMP/concurrent-home" python3 "$CONFIGURE" --user yanxi.chen@vanta.com >/dev/null &
configure_two=$!
wait "$configure_one" "$configure_two"
HOME="$TMP/concurrent-home" python3 -c '
from pathlib import Path
import tomllib

home = Path.home()
with (home / ".snowflake" / "connections.toml").open("rb") as file:
    connections = tomllib.load(file)
with (home / ".snowflake" / "config.toml").open("rb") as file:
    config = tomllib.load(file)
assert list(connections).count("JYFRXUC-VANTA") == 1
assert config["default_connection_name"] == "JYFRXUC-VANTA"
'

if HOME="$TMP/home" python3 "$CONFIGURE" --user someone@gmail.com >"$TMP/user.out" 2>"$TMP/user.err"; then
    fail "non-Vanta Snowflake user was accepted"
fi
assert_contains "$TMP/user.err" '@vanta.com'

AUTH="$ROOT/scripts/auth-vanta-data-apps-snowflake.sh"
cat >"$TMP/fake-auth-server.py" <<'EOF'
import os
import socket

port = int(os.environ["SF_AUTH_SOCKET_PORT"])
with socket.socket() as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    listener.listen()
    connection, _ = listener.accept()
    connection.close()

if os.environ.get("FAKE_AUTH_FAIL") == "true":
    raise SystemExit(1)
EOF

cat >"$TMP/bin/fake-auth-python" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >"$FAKE_AUTH_ARGS"
exec python3 "$FAKE_AUTH_SERVER"
EOF

cat >"$TMP/bin/ona-auth" <<'EOF'
#!/bin/sh
set -eu
[ "$*" = "environment get --context environment --field id" ] || exit 2
printf '%s\n' env-123
EOF

cat >"$TMP/bin/fake-bridge" <<'EOF'
#!/bin/sh
set -eu
command=$1
shift
printf '%s %s\n' "$command" "$*" >>"$FAKE_BRIDGE_LOG"
if [ "$command" = start ]; then
    callback=
    remote=
    environment=
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --callback-port) callback=$2; shift 2 ;;
            --remote-port) remote=$2; shift 2 ;;
            --environment-id) environment=$2; shift 2 ;;
            *) exit 2 ;;
        esac
    done
    printf 'Bridge ready. On your Mac, keep this foreground command running:\n'
    printf 'ona environment port forward %s --environment-id %s --local-port %s\n' \
        "$remote" "$environment" "$callback"
    python3 -c 'import socket, sys; socket.create_connection(("127.0.0.1", int(sys.argv[1]))).close()' "$callback"
fi
EOF

chmod +x "$TMP/bin/fake-auth-python" "$TMP/bin/ona-auth" "$TMP/bin/fake-bridge"
FAKE_AUTH_ARGS="$TMP/auth.args"
FAKE_AUTH_SERVER="$TMP/fake-auth-server.py"
FAKE_BRIDGE_LOG="$TMP/bridge.log"
export FAKE_AUTH_ARGS FAKE_AUTH_SERVER FAKE_BRIDGE_LOG

if HOME="$TMP/home" "$AUTH" --repo-dir "$TMP/data-apps" >"$TMP/noninteractive.out" 2>"$TMP/noninteractive.err"; then
    fail "Snowflake auth accepted non-interactive agent execution"
fi
assert_contains "$TMP/noninteractive.err" 'private interactive terminal'

pick_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

AUTH_CALLBACK_PORT=$(pick_port)
AUTH_REMOTE_PORT=$(pick_port)
while [ "$AUTH_REMOTE_PORT" = "$AUTH_CALLBACK_PORT" ]; do AUTH_REMOTE_PORT=$(pick_port); done
export AUTH_CALLBACK_PORT AUTH_REMOTE_PORT

SNOWFLAKE_AUTH_PYTHON="$TMP/bin/fake-auth-python"
SNOWFLAKE_AUTH_ONA="$TMP/bin/ona-auth"
ONA_OAUTH_CALLBACK_BRIDGE="$TMP/bin/fake-bridge"
SNOWFLAKE_AUTH_CALLBACK_PORT=$AUTH_CALLBACK_PORT
SNOWFLAKE_AUTH_REMOTE_PORT=$AUTH_REMOTE_PORT
export SNOWFLAKE_AUTH_PYTHON SNOWFLAKE_AUTH_ONA ONA_OAUTH_CALLBACK_BRIDGE
export SNOWFLAKE_AUTH_CALLBACK_PORT SNOWFLAKE_AUTH_REMOTE_PORT

script -qefc "'$AUTH' --repo-dir '$TMP/data-apps'" /dev/null >"$TMP/auth.out"
assert_contains "$FAKE_AUTH_ARGS" 'VANTA.VANTA_AI.LANGSMITH_TRACES'
assert_contains "$FAKE_AUTH_ARGS" 'SELECT * FROM {table} LIMIT 0'
assert_contains "$FAKE_BRIDGE_LOG" "start --callback-port $AUTH_CALLBACK_PORT --remote-port $AUTH_REMOTE_PORT --environment-id env-123"
assert_contains "$FAKE_BRIDGE_LOG" "stop --callback-port $AUTH_CALLBACK_PORT --remote-port $AUTH_REMOTE_PORT --environment-id env-123"
assert_contains "$TMP/auth.out" 'Restart Streamlit if it previously cached an authentication failure.'

: >"$FAKE_BRIDGE_LOG"
AUTH_CALLBACK_PORT=$(pick_port)
AUTH_REMOTE_PORT=$(pick_port)
while [ "$AUTH_REMOTE_PORT" = "$AUTH_CALLBACK_PORT" ]; do AUTH_REMOTE_PORT=$(pick_port); done
SNOWFLAKE_AUTH_CALLBACK_PORT=$AUTH_CALLBACK_PORT
SNOWFLAKE_AUTH_REMOTE_PORT=$AUTH_REMOTE_PORT
export SNOWFLAKE_AUTH_CALLBACK_PORT SNOWFLAKE_AUTH_REMOTE_PORT
if FAKE_AUTH_FAIL=true script -qefc "'$AUTH' --repo-dir '$TMP/data-apps'" \
        /dev/null >"$TMP/auth-fail.out" 2>"$TMP/auth-fail.err"; then
    fail "failed Snowflake validation was accepted"
fi
assert_contains "$FAKE_BRIDGE_LOG" "stop --callback-port $AUTH_CALLBACK_PORT --remote-port $AUTH_REMOTE_PORT --environment-id env-123"

if HOME="$TMP/home" \
        SNOWFLAKE_AUTH_PYTHON="$TMP/bin/fake-auth-python" \
        SNOWFLAKE_AUTH_ONA="$TMP/bin/ona-auth" \
        ONA_OAUTH_CALLBACK_BRIDGE="$TMP/bin/fake-bridge" \
        "$AUTH" --table 'VANTA.VANTA_AI.LANGSMITH_TRACES;DROP' >"$TMP/table.out" 2>"$TMP/table.err"; then
    fail "unsafe validation table was accepted"
fi
assert_contains "$TMP/table.err" 'three-part Snowflake identifier'
