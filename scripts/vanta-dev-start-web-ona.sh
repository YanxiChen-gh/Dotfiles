#!/usr/bin/env bash
# Start Vanta web with browser-safe assets, wait for nginx, then expose it.

set -euo pipefail

if [[ "${IS_ON_ONA:-}" != true ]]; then
    echo "vanta-dev-start-web-ona: this command is only for an Ona CDE." >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EXPOSE_PORT_SCRIPT="${EXPOSE_PORT_SCRIPT:-$SCRIPT_DIR/expose-port.sh}"
NGINX_PORT="${NGINX_PORT:-8080}"
READY_ATTEMPTS="${VANTA_DEV_READY_ATTEMPTS:-180}"

export PARCEL_PUBLIC_URL="${PARCEL_PUBLIC_URL:-/}"

just dev-start-web >&2

STATUS=unreachable
for _ in $(seq "$READY_ATTEMPTS"); do
    STATUS=$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' \
        "http://localhost:${NGINX_PORT}") || STATUS=unreachable
    if [[ "$STATUS" == 2* || "$STATUS" == 3* ]]; then
        exec "$EXPOSE_PORT_SCRIPT" "$NGINX_PORT" /
    fi
    sleep 5
done

echo "vanta-dev-start-web-ona: nginx did not become ready on localhost:${NGINX_PORT} (last status: ${STATUS})." >&2
exit 1
