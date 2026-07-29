#!/usr/bin/env bash
# Open a Lavish artifact and print one verified browser-accessible URL.

set -euo pipefail

usage() {
    echo "usage: open-lavish <html-file> [lavish-open-options]" >&2
}

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
    SOURCE_DIR=$(cd "$(dirname "$SOURCE")" && pwd)
    SOURCE=$(readlink "$SOURCE")
    [[ "$SOURCE" == /* ]] || SOURCE="$SOURCE_DIR/$SOURCE"
done
SCRIPT_DIR=$(cd "$(dirname "$SOURCE")" && pwd)

HTML_FILE="${1:-}"
if [[ -z "$HTML_FILE" ]]; then
    usage
    exit 2
fi
shift

LAVISH_PORT="${LAVISH_AXI_PORT:-4387}"
LOCK_FILE="${OPEN_LAVISH_LOCK_FILE:-/tmp/open-lavish-${LAVISH_PORT}.lock}"
PREPARE_SCRIPT="${OPEN_LAVISH_PREPARE_SCRIPT:-$SCRIPT_DIR/prepare-ona-tailnet.sh}"
EXPOSE_SCRIPT="${OPEN_LAVISH_EXPOSE_SCRIPT:-$SCRIPT_DIR/expose-port.sh}"

die() {
    echo "open-lavish: $*" >&2
    exit 1
}

run_lavish() {
    npx -y lavish-axi "$@"
}

probe_health() {
    local host_header="$1"
    local body_file="$2"
    local status
    if ! status=$(curl -sS --max-time 5 \
        -H "Host: ${host_header}" \
        -o "$body_file" -w '%{http_code}' \
        "http://127.0.0.1:${LAVISH_PORT}/health"); then
        status=unreachable
    fi
    printf '%s\n' "$status"
}

is_lavish_health() {
    jq -e '.ok == true and .app == "lavish-axi"' "$1" >/dev/null 2>&1
}

open_artifact() {
    local allowed_host="$1"
    local output
    shift
    if [[ -n "$allowed_host" ]]; then
        if ! output=$(LAVISH_AXI_HOST=127.0.0.1 \
            LAVISH_AXI_LINK_HOST=127.0.0.1 \
            LAVISH_AXI_ALLOWED_HOSTS="$allowed_host" \
            LAVISH_AXI_NO_OPEN=1 \
            run_lavish "$HTML_FILE" "$@"); then
            die "Lavish failed to open $HTML_FILE."
        fi
    elif ! output=$(run_lavish "$HTML_FILE" "$@"); then
        die "Lavish failed to open $HTML_FILE."
    fi
    printf '%s\n' "$output" >&2
    printf '%s\n' "$output" | sed -n 's/^[[:space:]]*url: "\([^"]*\)"[[:space:]]*$/\1/p' | tail -n 1
}

ALLOWED_HOST=""
HEALTH_DIR=""
if [[ "${IS_ON_ONA:-}" == true ]]; then
    [[ -x "$PREPARE_SCRIPT" ]] || die "tailnet preparation helper is not executable: $PREPARE_SCRIPT"
    ALLOWED_HOST=$($PREPARE_SCRIPT)

    exec 8>"$LOCK_FILE"
    flock 8

    HEALTH_DIR=$(mktemp -d)
    trap 'rm -rf "$HEALTH_DIR"' EXIT
    LOCAL_BODY="$HEALTH_DIR/local"
    PUBLIC_BODY="$HEALTH_DIR/public"
    LOCAL_STATUS=$(probe_health "127.0.0.1:${LAVISH_PORT}" "$LOCAL_BODY")

    if [[ "$LOCAL_STATUS" != unreachable ]]; then
        if [[ "$LOCAL_STATUS" != 2* ]] || ! is_lavish_health "$LOCAL_BODY"; then
            die "port ${LAVISH_PORT} is occupied by a service that is not a healthy Lavish server."
        fi

        PUBLIC_STATUS=$(probe_health "${ALLOWED_HOST}:8080" "$PUBLIC_BODY")
        if [[ "$PUBLIC_STATUS" == 2* ]] && is_lavish_health "$PUBLIC_BODY"; then
            :
        elif [[ "$PUBLIC_STATUS" == 403 ]] \
                && jq -e '.error == "forbidden host"' "$PUBLIC_BODY" >/dev/null 2>&1; then
            echo "open-lavish: restarting the shared Lavish server with ${ALLOWED_HOST} allowed." >&2
            run_lavish stop >&2 || die "could not stop the misconfigured Lavish server."
        else
            die "Lavish Host validation probe failed (${PUBLIC_STATUS}) for ${ALLOWED_HOST}."
        fi
    fi
fi

LOCAL_URL=$(open_artifact "$ALLOWED_HOST" "$@")
[[ -n "$LOCAL_URL" ]] || die "Lavish did not return a session URL."

if [[ "${IS_ON_ONA:-}" == true ]]; then
    FINAL_BODY="$HEALTH_DIR/final"
    FINAL_STATUS=$(probe_health "${ALLOWED_HOST}:8080" "$FINAL_BODY")
    if [[ "$FINAL_STATUS" != 2* ]] || ! is_lavish_health "$FINAL_BODY"; then
        die "Lavish did not retain the required Host allowlist after opening (${FINAL_STATUS})."
    fi
fi

URL_METADATA=$(python3 - "$LOCAL_URL" <<'PY'
from ipaddress import ip_address
import sys
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
try:
    loopback = ip_address(url.hostname or "").is_loopback
except ValueError:
    loopback = (url.hostname or "").lower() == "localhost"
if url.scheme != "http" or not loopback or url.port is None:
    raise SystemExit("Lavish returned a non-loopback URL")
path = url.path or "/"
if url.query:
    path += "?" + url.query
print(f"{url.port}\t{path}")
PY
)
IFS=$'\t' read -r URL_PORT URL_PATH <<<"$URL_METADATA"
if [[ -z "$URL_PORT" || -z "$URL_PATH" ]]; then
    die "could not parse Lavish session URL: $LOCAL_URL"
fi

if [[ "${IS_ON_ONA:-}" == true ]]; then
    flock -u 8
fi

if [[ -n "$HEALTH_DIR" ]]; then
    rm -rf "$HEALTH_DIR"
    trap - EXIT
fi

exec "$EXPOSE_SCRIPT" "$URL_PORT" "$URL_PATH"
