#!/bin/sh
# Herdr launches and interactive shells repair the durable CDE supervisor after resume.
if [ "${IS_ON_ONA:-}" = "true" ] || [ "${CURSOR_CLOUD:-}" = "1" ]; then
    hub_command="$HOME/.local/bin/omp-session-hub"
    if [ -x "$hub_command" ]; then
        launcher_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 0
        set -- service ensure hub --adapter "$launcher_dir/session-hub-adapter.py"
        if [ -n "${OMP_SESSION_HUB_PORT:-}" ]; then
            set -- "$@" --port "$OMP_SESSION_HUB_PORT"
        fi
        "$hub_command" "$@" >/dev/null 2>&1 || true
    fi
fi
