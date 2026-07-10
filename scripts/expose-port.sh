#!/usr/bin/env bash
# Return a verified browser-accessible URL for a local HTTP server.
#
# Usage: expose-port.sh [--local] <local-port> [verify-path]
#
# Auto mode uses the Ona Tailscale path in a CDE, localhost on macOS, and fails
# closed on unknown remote Linux environments. The final URL is the only stdout;
# progress and errors go to stderr so agents can use command substitution safely.

set -euo pipefail

usage() {
    echo "usage: expose-port.sh [--local] <local-port> [verify-path]" >&2
}

MODE=auto
case "${1:-}" in
    --local)
        MODE=local
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

if [[ "$MODE" == auto ]]; then
    if [[ "${IS_ON_ONA:-}" == true ]]; then
        MODE=tailscale
    elif [[ "$(uname -s)" == Darwin ]]; then
        MODE=local
    else
        echo "expose-port: cannot infer browser reachability outside Ona on this host." >&2
        echo "expose-port: use --local only when the browser shares localhost; otherwise use the editor port-forward." >&2
        exit 1
    fi
fi

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
    echo "expose-port: local verification failed (${STATUS}) for ${URL}" >&2
    exit 1
fi

echo "expose-port: verified local URL (${STATUS})." >&2
echo "$URL"
