#!/usr/bin/env bash

configure_lavish_session_env() {
    local artifact_file="$1"
    local artifact_path
    local state_root
    local state_dir
    local port_file
    local port

    if [[ -n "${LAVISH_AXI_PORT:-}" || -n "${LAVISH_AXI_STATE_DIR:-}" ]]; then
        return
    fi

    artifact_path=$(realpath "$artifact_file")
    state_root="${LAVISH_SESSION_STATE_ROOT:-$HOME/.lavish-axi}"
    state_dir="$state_root/sessions/$(printf '%s' "$artifact_path" | sha256sum | cut -c1-16)"
    port_file="$state_dir/port"
    mkdir -p "$state_dir"

    exec 9>"$state_root/session-port-allocation.lock"
    flock 9
    if [[ -s "$port_file" ]]; then
        IFS= read -r port <"$port_file"
    else
        while :; do
            port=$(python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
    listener.bind(("127.0.0.1", 0))
    print(listener.getsockname()[1])
PY
)
            if ! grep -Rqx -- "$port" "$state_root/sessions"/*/port 2>/dev/null; then
                printf '%s\n' "$port" >"$port_file"
                break
            fi
        done
    fi
    flock -u 9
    exec 9>&-

    export LAVISH_AXI_PORT="$port"
    export LAVISH_AXI_STATE_DIR="$state_dir"
}
