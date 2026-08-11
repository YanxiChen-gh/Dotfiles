#!/usr/bin/env bash
# Return a loopback URL for a verified HTTP service.
#
# Usage: expose-port.sh [--local|--tailscale] <local-port> [verify-path]
#
# The default returns a loopback URL after verifying the service on this host. In
# a remote environment, an automatic SSH forwarder is expected to make that same
# port available on the user's machine. Tailscale remains an explicit fallback.
# The final URL is the only stdout so agents can use command substitution safely.

set -euo pipefail

usage() {
    echo "usage: expose-port.sh [--local|--tailscale] <local-port> [verify-path]" >&2
}

MODE=auto
case "${1:-}" in
    --local)
        MODE=local
        shift
        ;;
    --tailscale)
        MODE=tailscale
        shift
        ;;
    --help|-h)
        usage
        exit 0
        ;;
esac

LOCAL_PORT="${1:-}"
VERIFY_PATH="${2:-/}"

if [[ -z "$LOCAL_PORT" || ! "$LOCAL_PORT" =~ ^[0-9]+$ ]] \
        || (( 10#$LOCAL_PORT < 1 || 10#$LOCAL_PORT > 65535 )); then
    echo "expose-port: local port must be an integer from 1 to 65535." >&2
    usage
    exit 2
fi
if [[ "$VERIFY_PATH" != /* ]]; then
    echo "expose-port: verify path must start with '/'." >&2
    exit 2
fi

[[ "$MODE" == auto ]] && MODE=local

if [[ "$MODE" == tailscale ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TAILSCALE_SCRIPT="${EXPOSE_PORT_TAILSCALE_SCRIPT:-$SCRIPT_DIR/expose-port-tailscale.sh}"
    if [[ ! -x "$TAILSCALE_SCRIPT" ]]; then
        echo "expose-port: Tailscale implementation is not executable: $TAILSCALE_SCRIPT" >&2
        exit 1
    fi
    exec "$TAILSCALE_SCRIPT" "$LOCAL_PORT" "$VERIFY_PATH"
fi

URL="http://127.0.0.1:${LOCAL_PORT}${VERIFY_PATH}"
STATUS=$(curl -s --max-time 15 -o /dev/null -w '%{http_code}' "$URL") || STATUS=unreachable
if [[ "$STATUS" != 2* && "$STATUS" != 3* ]]; then
    echo "expose-port: loopback service verification failed (${STATUS}) for ${URL}" >&2
    exit 1
fi

echo "expose-port: verified loopback service (${STATUS}); automatic port forwarding is assumed." >&2
echo "$URL"
