#!/usr/bin/env bash
# Start Vanta web with browser-safe assets, wait for nginx, then expose it.

set -euo pipefail

if [[ "${IS_ON_ONA:-}" != true ]]; then
    echo "vanta-dev-start-web-ona: this command is only for an Ona CDE." >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EXPOSE_PORT_SCRIPT="${EXPOSE_PORT_SCRIPT:-$SCRIPT_DIR/expose-port.sh}"
BROWSER_ASSET_CHECKER="${BROWSER_ASSET_CHECKER:-$SCRIPT_DIR/find-loopback-browser-asset.py}"
NGINX_PORT="${NGINX_PORT:-8080}"
READY_ATTEMPTS="${VANTA_DEV_READY_ATTEMPTS:-180}"

export PARCEL_PUBLIC_URL="${PARCEL_PUBLIC_URL:-/}"

just dev-start-web >&2

VERIFY_TMP=$(mktemp -d)
trap 'rm -rf "$VERIFY_TMP"' EXIT
ROOT_BODY="$VERIFY_TMP/root.html"
ROOT_STATUS=unreachable
ROOT_CONTENT_TYPE=
OFFENDING_URL=

fetch_root() {
    local curl_meta

    if curl_meta=$(curl -s --show-error --location --max-time 3 \
        -o "$ROOT_BODY" -w $'%{http_code}\n%{content_type}' \
        "http://localhost:${NGINX_PORT}/"); then
        ROOT_STATUS=${curl_meta%%$'\n'*}
        ROOT_CONTENT_TYPE=${curl_meta#*$'\n'}
    else
        ROOT_STATUS=unreachable
        ROOT_CONTENT_TYPE=
        return 1
    fi
    if [[ "$ROOT_STATUS" != 2* && "$ROOT_STATUS" != 3* ]]; then
        return 1
    fi
    case "${ROOT_CONTENT_TYPE,,}" in
        text/html*|application/xhtml+xml*) return 0 ;;
        *) return 1 ;;
    esac
}

wait_for_root() {
    for _ in $(seq "$READY_ATTEMPTS"); do
        if fetch_root; then
            return 0
        fi
        sleep 5
    done
    return 1
}

inspect_root() {
    if ! OFFENDING_URL=$(python3 "$BROWSER_ASSET_CHECKER" "$ROOT_BODY"); then
        echo "vanta-dev-start-web-ona: could not inspect the root HTML response." >&2
        return 2
    fi
    [[ -z "$OFFENDING_URL" ]]
}

expose_root() {
    rm -rf "$VERIFY_TMP"
    trap - EXIT
    exec "$EXPOSE_PORT_SCRIPT" "$NGINX_PORT" /
}

if ! wait_for_root; then
    echo "vanta-dev-start-web-ona: root page did not become ready on localhost:${NGINX_PORT} (last status: ${ROOT_STATUS}, content type: ${ROOT_CONTENT_TYPE:-unknown})." >&2
    exit 1
fi

if inspect_root; then
    expose_root
else
    inspect_status=$?
    if [[ "$inspect_status" == 2 ]]; then
        exit 1
    fi
fi

echo "vanta-dev-start-web-ona: browser-active asset uses CDE loopback: ${OFFENDING_URL}; replacing web-client." >&2
PARCEL_PUBLIC_URL=/ just dev-replace web-client >&2
OFFENDING_URL=

for _ in $(seq "$READY_ATTEMPTS"); do
    if fetch_root; then
        if inspect_root; then
            expose_root
        else
            inspect_status=$?
            if [[ "$inspect_status" == 2 ]]; then
                exit 1
            fi
        fi
    fi
    sleep 5
done

if [[ -n "$OFFENDING_URL" ]]; then
    echo "vanta-dev-start-web-ona: browser-active asset still uses CDE loopback after replacing web-client: ${OFFENDING_URL}" >&2
else
    echo "vanta-dev-start-web-ona: root page did not become ready after replacing web-client (last status: ${ROOT_STATUS}, content type: ${ROOT_CONTENT_TYPE:-unknown})." >&2
fi
exit 1
