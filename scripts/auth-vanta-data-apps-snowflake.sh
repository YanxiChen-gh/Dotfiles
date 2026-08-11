#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_DIR=${DATA_APPS_DIR:-/workspaces/data-apps}
CONNECTION_NAME=${SNOWFLAKE_CONNECTION_NAME:-JYFRXUC-VANTA}
VALIDATION_TABLE=${SNOWFLAKE_VALIDATION_TABLE:-VANTA.VANTA_AI.LANGSMITH_TRACES}
BRIDGE=${ONA_OAUTH_CALLBACK_BRIDGE:-$DOTFILES_DIR/shared-skills/ona-oauth-callback/bridge.sh}
ONA_COMMAND=${SNOWFLAKE_AUTH_ONA:-ona}
PORT_PYTHON=${SNOWFLAKE_AUTH_PORT_PYTHON:-python3}
SS_COMMAND=${SNOWFLAKE_AUTH_SS:-ss}
CALLBACK_PORT=${SNOWFLAKE_AUTH_CALLBACK_PORT:-}
REMOTE_PORT=${SNOWFLAKE_AUTH_REMOTE_PORT:-}

usage() {
    cat <<'EOF'
Usage: auth-vanta-data-apps-snowflake.sh [--repo-dir DIR] [--table DATABASE.SCHEMA.TABLE]

Refresh the cached Snowflake external-browser credential for Vanta data apps.
The helper prints an authorization URL and an exact Mac port-forward command.
It never captures the redirect URL, authorization code, or token.
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --repo-dir)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            REPO_DIR=$2
            shift 2
            ;;
        --table)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            VALIDATION_TABLE=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! "$VALIDATION_TABLE" =~ ^[A-Za-z_][A-Za-z0-9_$]*\.[A-Za-z_][A-Za-z0-9_$]*\.[A-Za-z_][A-Za-z0-9_$]*$ ]]; then
    echo "Validation table must be a three-part Snowflake identifier." >&2
    exit 2
fi
if [[ ! -t 0 || ! -t 1 || ! -t 2 ]]; then
    echo "Run this command yourself in a private interactive terminal; SSO URLs must not enter an agent transcript." >&2
    exit 1
fi
if [[ ! -x "$BRIDGE" ]]; then
    echo "Ona OAuth callback bridge is unavailable: $BRIDGE" >&2
    exit 1
fi
if ! command -v "$ONA_COMMAND" >/dev/null 2>&1; then
    echo "Ona CLI is required for callback forwarding." >&2
    exit 1
fi
if ! command -v "$PORT_PYTHON" >/dev/null 2>&1; then
    echo "Python 3 is required to allocate callback ports." >&2
    exit 1
fi
if ! command -v "$SS_COMMAND" >/dev/null 2>&1; then
    echo "ss is required to verify the callback listener." >&2
    exit 1
fi

SNOWFLAKE_PYTHON=${SNOWFLAKE_AUTH_PYTHON:-$REPO_DIR/venv/bin/python}
if [[ ! -x "$SNOWFLAKE_PYTHON" ]]; then
    echo "data-apps virtualenv is missing: $SNOWFLAKE_PYTHON" >&2
    echo "Run $SCRIPT_DIR/setup-vanta-data-apps.sh first." >&2
    exit 1
fi
if [[ ! -f "$HOME/.snowflake/connections.toml" || ! -f "$HOME/.snowflake/config.toml" ]]; then
    echo "Snowflake profile is missing. Run $SCRIPT_DIR/setup-vanta-data-apps.sh first." >&2
    exit 1
fi

mkdir -p "$HOME/.cache/snowflake"
chmod 700 "$HOME/.cache/snowflake"

pick_port() {
    "$PORT_PYTHON" -c '
import socket

with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    print(listener.getsockname()[1])
'
}

[[ -n "$CALLBACK_PORT" ]] || CALLBACK_PORT=$(pick_port)
if [[ -z "$REMOTE_PORT" ]]; then
    REMOTE_PORT=$(pick_port)
    while [[ "$REMOTE_PORT" == "$CALLBACK_PORT" ]]; do
        REMOTE_PORT=$(pick_port)
    done
fi
if [[ ! "$CALLBACK_PORT" =~ ^[0-9]+$ || ! "$REMOTE_PORT" =~ ^[0-9]+$ ]] \
        || (( 10#$CALLBACK_PORT < 1 || 10#$CALLBACK_PORT > 65535 )) \
        || (( 10#$REMOTE_PORT < 1 || 10#$REMOTE_PORT > 65535 )) \
        || (( 10#$CALLBACK_PORT == 10#$REMOTE_PORT )); then
    echo "Callback and remote ports must be distinct valid ports." >&2
    exit 1
fi

environment_output=$("$ONA_COMMAND" environment get --context environment --field id 2>/dev/null) \
    || { echo "Could not resolve the current Ona environment ID." >&2; exit 1; }
mapfile -t environment_ids <<<"$environment_output"
if (( ${#environment_ids[@]} != 1 )) || [[ ! "${environment_ids[0]}" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,127}$ ]]; then
    echo "Expected exactly one valid Ona environment ID." >&2
    exit 1
fi
ENVIRONMENT_ID=${environment_ids[0]}

auth_pid=
bridge_started=false
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ "$bridge_started" == true ]]; then
        "$BRIDGE" stop \
            --callback-port "$CALLBACK_PORT" \
            --remote-port "$REMOTE_PORT" \
            --environment-id "$ENVIRONMENT_ID" || status=1
    fi
    if [[ -n "$auth_pid" ]] && kill -0 "$auth_pid" 2>/dev/null; then
        kill "$auth_pid" 2>/dev/null || true
        wait "$auth_pid" 2>/dev/null || true
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Starting Snowflake SSO. Keep this terminal open and do not paste redirect URLs into chat."
SF_AUTH_SOCKET_PORT="$CALLBACK_PORT" \
SNOWFLAKE_AUTH_FORCE_SERVER=true \
"$SNOWFLAKE_PYTHON" -c '
import snowflake.connector
import sys

connection_name, table = sys.argv[1:]
connection = snowflake.connector.connect(connection_name=connection_name)
try:
    connection.cursor().execute(f"SELECT * FROM {table} LIMIT 0")
finally:
    connection.close()
' "$CONNECTION_NAME" "$VALIDATION_TABLE" &
auth_pid=$!

callback_ready=false
for _ in {1..300}; do
    if ! kill -0 "$auth_pid" 2>/dev/null; then
        if wait "$auth_pid"; then
            auth_pid=
            echo "Snowflake authentication and table access are already valid."
            exit 0
        fi
        auth_pid=
        echo "Snowflake authentication exited before opening its callback listener." >&2
        exit 1
    fi
    if "$SS_COMMAND" -H -ltn "sport = :$CALLBACK_PORT" 2>/dev/null \
            | grep -Eq "127\\.0\\.0\\.1:${CALLBACK_PORT}([[:space:]]|$)"; then
        callback_ready=true
        break
    fi
    sleep 0.1
done
[[ "$callback_ready" == true ]] || { echo "Snowflake callback did not become ready." >&2; exit 1; }

"$BRIDGE" start \
    --callback-port "$CALLBACK_PORT" \
    --remote-port "$REMOTE_PORT" \
    --environment-id "$ENVIRONMENT_ID"
bridge_started=true

echo "Run the printed command on your Mac, then open the Snowflake authorization URL above."
if ! wait "$auth_pid"; then
    auth_pid=
    echo "Snowflake authentication or table validation failed." >&2
    exit 1
fi
auth_pid=

echo "Snowflake SSO and access to $VALIDATION_TABLE are valid."
echo "Restart Streamlit if it previously cached an authentication failure."
