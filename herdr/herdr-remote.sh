#!/bin/sh
set -eu

usage() {
    echo "Usage: herdr-remote <ssh-target> [herdr remote options]" >&2
    exit 2
}

resolve_script_dir() {
    script_path=$0
    while [ -L "$script_path" ]; do
        link=$(readlink "$script_path")
        case "$link" in
            /*) script_path=$link ;;
            *) script_path=$(dirname "$script_path")/$link ;;
        esac
    done
    CDPATH= cd -- "$(dirname "$script_path")" && pwd -P
}

[ "$#" -ge 1 ] || usage
target=$1
shift
case "$target" in
    ""|-*) usage ;;
esac

for command_name in herdr lsof python3 ssh; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "herdr-remote: $command_name is required" >&2
        exit 1
    fi
done

script_dir=$(resolve_script_dir)
relay_script="$script_dir/remote-opener/open_url.py"
if [ ! -f "$relay_script" ]; then
    echo "herdr-remote: relay script not found at $relay_script" >&2
    exit 1
fi
relay_port=$(python3 "$relay_script" --print-port)
opener_socket=${OPENER_SOCKET_PATH:-$HOME/.opener.sock}
if [ ! -S "$opener_socket" ]; then
    echo "herdr-remote: opener is not listening at $opener_socket" >&2
    echo "Start it with: brew services start opener" >&2
    exit 1
fi
if ! lsof -t "$opener_socket" >/dev/null 2>&1; then
    echo "herdr-remote: no opener process owns $opener_socket" >&2
    echo "Restart it with: brew services restart opener" >&2
    exit 1
fi

state_dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-opener.XXXXXX")
control_socket="$state_dir/ssh"
proxy_socket="$state_dir/opener.sock"
proxy_pid=""
tunnel_started=false
cleanup() {
    if [ "$tunnel_started" = true ]; then
        ssh -S "$control_socket" -O exit "$target" >/dev/null 2>&1 || true
    fi
    if [ -n "$proxy_pid" ]; then
        kill "$proxy_pid" 2>/dev/null || true
        wait "$proxy_pid" 2>/dev/null || true
    fi
    rm -rf "$state_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "$relay_script" --proxy "$proxy_socket" "$opener_socket" &
proxy_pid=$!
for _ in $(seq 1 100); do
    if [ -S "$proxy_socket" ]; then
        break
    fi
    if ! kill -0 "$proxy_pid" 2>/dev/null; then
        wait "$proxy_pid" 2>/dev/null || true
        echo "herdr-remote: opener proxy failed to start" >&2
        exit 1
    fi
    sleep 0.01
done
if [ ! -S "$proxy_socket" ]; then
    echo "herdr-remote: opener proxy did not become ready" >&2
    exit 1
fi

if ! ssh -M -S "$control_socket" -fNT \
    -o ControlPersist=no \
    -o ExitOnForwardFailure=yes \
    -o GatewayPorts=no \
    -R "127.0.0.1:${relay_port}:$proxy_socket" \
    -- "$target"; then
    echo "herdr-remote: could not establish the browser relay to $target" >&2
    exit 1
fi
tunnel_started=true
listener=$(ssh -S "$control_socket" "$target" \
    "ss -ltnH 'sport = :$relay_port' | awk '{print \$4}'" 2>/dev/null || true)
if [ "$listener" != "127.0.0.1:$relay_port" ]; then
    echo "herdr-remote: expected a loopback relay, got ${listener:-no listener}" >&2
    echo "The remote host needs ss and sshd GatewayPorts no or clientspecified." >&2
    exit 1
fi

herdr --remote "$target" "$@"
