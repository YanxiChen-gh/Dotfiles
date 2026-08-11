#!/usr/bin/env bash

set -euo pipefail

ONA_COMMAND=${ONA_OAUTH_CALLBACK_ONA:-ona}
TMUX_COMMAND=${ONA_OAUTH_CALLBACK_TMUX:-tmux}
SS_COMMAND=${ONA_OAUTH_CALLBACK_SS:-ss}
SOCAT_COMMAND=${ONA_OAUTH_CALLBACK_SOCAT:-socat}
STATE_DIR=${ONA_OAUTH_CALLBACK_STATE_DIR:-${TMPDIR:-/tmp}/ona-oauth-callback}

usage() {
    cat <<'EOF'
Usage:
  bridge.sh start --callback-port PORT --remote-port PORT --environment-id ID
  bridge.sh status --remote-port PORT
  bridge.sh stop --callback-port PORT --remote-port PORT --environment-id ID
EOF
}

die() {
    echo "ona-oauth-callback: $*" >&2
    exit 1
}

validate_port() {
    local label=$1
    local value=$2
    [[ "$value" =~ ^[0-9]+$ ]] || die "$label must be an integer."
    (( 10#$value >= 1 && 10#$value <= 65535 )) || die "$label must be from 1 to 65535."
}

validate_environment_id() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,127}$ ]] \
        || die "environment ID contains unsupported characters."
}

require_commands() {
    local command
    for command in "$ONA_COMMAND" "$TMUX_COMMAND" "$SS_COMMAND" "$SOCAT_COMMAND" flock python3; do
        command -v "$command" >/dev/null 2>&1 || die "required command is unavailable: $command"
    done
}

socket_output() {
    "$SS_COMMAND" -H -ltn "sport = :$1" 2>/dev/null || true
}

require_loopback_callback() {
    local output
    output=$(socket_output "$CALLBACK_PORT")
    [[ -n "$output" ]] || die "no callback listener found on 127.0.0.1:$CALLBACK_PORT."
    if ! grep -Eq "127\\.0\\.0\\.1:${CALLBACK_PORT}([[:space:]]|$)" <<<"$output"; then
        die "callback must listen on exactly 127.0.0.1:$CALLBACK_PORT."
    fi
    if grep -Eq "(0\\.0\\.0\\.0|\\[::\\]|\\*):${CALLBACK_PORT}([[:space:]]|$)" <<<"$output"; then
        die "callback port also has a non-loopback listener; refusing to bridge it."
    fi
}

remote_listener_state() {
    [[ -n "$(socket_output "$1")" ]] && echo listening || echo absent
}

registration_state() {
    local environment_id=$1
    local remote_port=$2
    local expected_name=$3
    local current_name
    local listing
    local presence

    if current_name=$("$ONA_COMMAND" environment port get "$remote_port" \
            --environment-id "$environment_id" --field name 2>/dev/null); then
        if [[ "$current_name" == "$expected_name" ]]; then
            echo owned
        else
            echo replaced
        fi
        return
    fi

    if ! listing=$("$ONA_COMMAND" environment port list "$environment_id" --format json 2>/dev/null); then
        echo unknown
        return
    fi
    presence=$(python3 -c '
import json
import sys

port = int(sys.argv[1])
try:
    entries = json.load(sys.stdin)
except (json.JSONDecodeError, TypeError):
    print("unknown")
    raise SystemExit

if not isinstance(entries, list):
    print("unknown")
elif any(isinstance(entry, dict) and entry.get("port") == port for entry in entries):
    print("present")
else:
    print("absent")
' "$remote_port" <<<"$listing")
    [[ "$presence" == absent ]] && echo absent || echo unknown
}

session_state() {
    local session=$1
    local ownership_id=$2
    local marker
    if ! "$TMUX_COMMAND" has-session -t "$session" 2>/dev/null; then
        echo absent
        return
    fi
    marker=$("$TMUX_COMMAND" show-environment -t "$session" \
        ONA_OAUTH_CALLBACK_OWNERSHIP 2>/dev/null || true)
    if [[ "$marker" == "ONA_OAUTH_CALLBACK_OWNERSHIP=$ownership_id" ]]; then
        echo owned
    else
        echo replaced
    fi
}

write_state() {
    umask 077
    cat >"$STATE_FILE" <<EOF
version=1
callback_port=$CALLBACK_PORT
remote_port=$REMOTE_PORT
environment_id=$ENVIRONMENT_ID
session=$SESSION
ownership_id=$OWNERSHIP_ID
registration_name=$REGISTRATION_NAME
EOF
    chmod 600 "$STATE_FILE"
}

load_state() {
    local key
    local value
    [[ -f "$STATE_FILE" ]] || die "owned state is absent at $STATE_FILE; refusing to adopt resources."

    STATE_VERSION=
    STATE_CALLBACK_PORT=
    STATE_REMOTE_PORT=
    STATE_ENVIRONMENT_ID=
    STATE_SESSION=
    STATE_OWNERSHIP_ID=
    STATE_REGISTRATION_NAME=
    while IFS='=' read -r key value; do
        case "$key" in
            version) STATE_VERSION=$value ;;
            callback_port) STATE_CALLBACK_PORT=$value ;;
            remote_port) STATE_REMOTE_PORT=$value ;;
            environment_id) STATE_ENVIRONMENT_ID=$value ;;
            session) STATE_SESSION=$value ;;
            ownership_id) STATE_OWNERSHIP_ID=$value ;;
            registration_name) STATE_REGISTRATION_NAME=$value ;;
            *) die "owned state contains an unknown field."
        esac
    done <"$STATE_FILE"

    [[ "$STATE_VERSION" == 1 ]] || die "owned state has an unsupported version."
    validate_port "state callback port" "$STATE_CALLBACK_PORT"
    validate_port "state remote port" "$STATE_REMOTE_PORT"
    validate_environment_id "$STATE_ENVIRONMENT_ID"
    [[ "$STATE_SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || die "owned state has an invalid session."
    [[ "$STATE_OWNERSHIP_ID" =~ ^[a-f0-9]{16}$ ]] || die "owned state has an invalid ownership ID."
    [[ "$STATE_REGISTRATION_NAME" =~ ^[A-Za-z0-9_-]+$ ]] \
        || die "owned state has an invalid registration name."
}

rollback_start() {
    local current_registration
    local cleanup_complete=true
    if [[ -n "${REGISTRATION_NAME:-}" ]]; then
        current_registration=$(registration_state "$ENVIRONMENT_ID" "$REMOTE_PORT" "$REGISTRATION_NAME")
        if [[ "$current_registration" == owned ]]; then
            if ! "$ONA_COMMAND" environment port close "$REMOTE_PORT" \
                    --environment-id "$ENVIRONMENT_ID" >/dev/null 2>&1; then
                cleanup_complete=false
            fi
        elif [[ "$current_registration" != absent ]]; then
            cleanup_complete=false
        fi
    fi
    if [[ -n "${SESSION:-}" ]] && "$TMUX_COMMAND" has-session -t "$SESSION" 2>/dev/null; then
        if ! "$TMUX_COMMAND" kill-session -t "$SESSION" >/dev/null 2>&1 \
                || "$TMUX_COMMAND" has-session -t "$SESSION" 2>/dev/null; then
            cleanup_complete=false
        fi
    fi
    if [[ "$cleanup_complete" == true ]]; then
        rm -f "$STATE_FILE"
    else
        echo "ona-oauth-callback: start rollback was partial; ownership state remains at $STATE_FILE." >&2
    fi
}

start_bridge() {
    local bridge_command
    local registration
    local ready=0

    [[ -n "$CALLBACK_PORT" && -n "$REMOTE_PORT" && -n "$ENVIRONMENT_ID" ]] \
        || die "start requires --callback-port, --remote-port, and --environment-id."
    validate_port "callback port" "$CALLBACK_PORT"
    validate_port "remote port" "$REMOTE_PORT"
    validate_environment_id "$ENVIRONMENT_ID"
    (( 10#$CALLBACK_PORT != 10#$REMOTE_PORT )) || die "callback and remote ports must differ."
    [[ ! -e "$STATE_FILE" ]] || die "owned state already exists at $STATE_FILE."
    require_loopback_callback
    [[ "$(remote_listener_state "$REMOTE_PORT")" == absent ]] \
        || die "remote port $REMOTE_PORT already has a listener."
    registration=$(registration_state "$ENVIRONMENT_ID" "$REMOTE_PORT" "")
    [[ "$registration" == absent ]] || die "remote port $REMOTE_PORT already has an Ona registration or could not be verified."

    OWNERSHIP_ID=$(python3 -c 'import secrets; print(secrets.token_hex(8))')
    SESSION="ona-oauth-callback-${REMOTE_PORT}-${OWNERSHIP_ID}"
    REGISTRATION_NAME="ona-oauth-callback-${REMOTE_PORT}-${OWNERSHIP_ID}"
    write_state
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'status=$?; trap - EXIT INT TERM; if (( status != 0 )); then rollback_start; fi; exit "$status"' EXIT

    printf -v bridge_command 'exec %q %q %q' "$SOCAT_COMMAND" \
        "TCP-LISTEN:${REMOTE_PORT},bind=0.0.0.0,reuseaddr,fork" \
        "TCP:127.0.0.1:${CALLBACK_PORT}"
    "$TMUX_COMMAND" new-session -d -s "$SESSION" "$bridge_command"
    "$TMUX_COMMAND" set-environment -t "$SESSION" \
        ONA_OAUTH_CALLBACK_OWNERSHIP "$OWNERSHIP_ID"

    for _ in {1..30}; do
        if [[ "$(session_state "$SESSION" "$OWNERSHIP_ID")" == owned ]] \
                && [[ "$(remote_listener_state "$REMOTE_PORT")" == listening ]]; then
            ready=1
            break
        fi
        sleep 0.1
    done
    (( ready == 1 )) || die "managed callback bridge did not become ready."

    "$ONA_COMMAND" environment port open "$REMOTE_PORT" \
        --environment-id "$ENVIRONMENT_ID" \
        --admission creator_only \
        --protocol http \
        --name "$REGISTRATION_NAME" >/dev/null
    [[ "$(registration_state "$ENVIRONMENT_ID" "$REMOTE_PORT" "$REGISTRATION_NAME")" == owned ]] \
        || die "owned Ona registration could not be verified."

    trap - EXIT INT TERM
    printf 'Bridge ready. On your Mac, keep this foreground command running:\n'
    printf 'ona environment port forward %s --environment-id %s --local-port %s\n' \
        "$REMOTE_PORT" "$ENVIRONMENT_ID" "$CALLBACK_PORT"
    printf 'Keep that command and the original OAuth CLI running until the callback completes.\n'
    printf 'Cleanup: %s stop --callback-port %s --remote-port %s --environment-id %s\n' \
        "$0" "$CALLBACK_PORT" "$REMOTE_PORT" "$ENVIRONMENT_ID"
}

status_bridge() {
    local current_registration
    local current_session
    [[ -n "$REMOTE_PORT" && -z "$CALLBACK_PORT" && -z "$ENVIRONMENT_ID" ]] \
        || die "status accepts only --remote-port."
    validate_port "remote port" "$REMOTE_PORT"
    load_state
    current_registration=$(registration_state "$STATE_ENVIRONMENT_ID" "$STATE_REMOTE_PORT" \
        "$STATE_REGISTRATION_NAME")
    current_session=$(session_state "$STATE_SESSION" "$STATE_OWNERSHIP_ID")
    printf 'Owned callback: 127.0.0.1:%s -> 0.0.0.0:%s\n' \
        "$STATE_CALLBACK_PORT" "$STATE_REMOTE_PORT"
    printf 'Managed tmux session: %s\n' "$current_session"
    printf 'Ona registration: %s\n' "$current_registration"
}

stop_bridge() {
    local current_registration
    local current_session
    local partial=0
    [[ -n "$CALLBACK_PORT" && -n "$REMOTE_PORT" && -n "$ENVIRONMENT_ID" ]] \
        || die "stop requires --callback-port, --remote-port, and --environment-id."
    validate_port "callback port" "$CALLBACK_PORT"
    validate_port "remote port" "$REMOTE_PORT"
    validate_environment_id "$ENVIRONMENT_ID"
    load_state
    [[ "$CALLBACK_PORT" == "$STATE_CALLBACK_PORT" \
        && "$REMOTE_PORT" == "$STATE_REMOTE_PORT" \
        && "$ENVIRONMENT_ID" == "$STATE_ENVIRONMENT_ID" ]] \
        || die "cleanup arguments do not match the owned state."

    current_registration=$(registration_state "$STATE_ENVIRONMENT_ID" "$STATE_REMOTE_PORT" \
        "$STATE_REGISTRATION_NAME")
    case "$current_registration" in
        owned)
            "$ONA_COMMAND" environment port close "$STATE_REMOTE_PORT" \
                --environment-id "$STATE_ENVIRONMENT_ID" >/dev/null
            ;;
        absent) ;;
        *)
            echo "ona-oauth-callback: refusing to close an unowned or unverifiable Ona registration." >&2
            partial=1
            ;;
    esac

    current_session=$(session_state "$STATE_SESSION" "$STATE_OWNERSHIP_ID")
    case "$current_session" in
        owned) "$TMUX_COMMAND" kill-session -t "$STATE_SESSION" >/dev/null ;;
        absent) ;;
        *)
            echo "ona-oauth-callback: refusing to stop an unowned tmux session." >&2
            partial=1
            ;;
    esac

    if (( partial != 0 )); then
        die "cleanup was partial; ownership state remains at $STATE_FILE."
    fi
    rm -f "$STATE_FILE"
    echo "Owned Ona registration and callback bridge are clean."
}

COMMAND=${1:-}
[[ -n "$COMMAND" ]] || { usage >&2; exit 2; }
shift
CALLBACK_PORT=
REMOTE_PORT=
ENVIRONMENT_ID=
while (( $# > 0 )); do
    case "$1" in
        --callback-port) [[ $# -ge 2 ]] || die "--callback-port needs a value"; CALLBACK_PORT=$2; shift 2 ;;
        --remote-port) [[ $# -ge 2 ]] || die "--remote-port needs a value"; REMOTE_PORT=$2; shift 2 ;;
        --environment-id) [[ $# -ge 2 ]] || die "--environment-id needs a value"; ENVIRONMENT_ID=$2; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
if [[ -n "$REMOTE_PORT" ]]; then
    validate_port "remote port" "$REMOTE_PORT"
    REMOTE_PORT=$((10#$REMOTE_PORT))
    STATE_FILE="$STATE_DIR/ona-oauth-callback-${REMOTE_PORT}.state"
    LOCK_FILE="$STATE_DIR/ona-oauth-callback-${REMOTE_PORT}.lock"
    exec 9>"$LOCK_FILE"
    flock 9
else
    STATE_FILE=
fi

require_commands
case "$COMMAND" in
    start) start_bridge ;;
    status) status_bridge ;;
    stop) stop_bridge ;;
    *) usage >&2; exit 2 ;;
esac
