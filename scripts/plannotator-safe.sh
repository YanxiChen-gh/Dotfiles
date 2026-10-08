#!/bin/sh
# Keep agent review sessions private; URL opening belongs to the host.
for arg in "$@"; do
    case "$arg" in
        --tailscale|--open)
            printf 'plannotator-safe: %s bypasses private, host-managed review\n' "$arg" >&2
            exit 2
            ;;
    esac
done
export PLANNOTATOR_REMOTE=0
export PLANNOTATOR_SKIP_BROWSER_OPEN=1
export PLANNOTATOR_GLIMPSE=0
export PLANNOTATOR_SHARE=disabled
exec plannotator "$@"
