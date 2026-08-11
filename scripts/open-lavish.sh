#!/usr/bin/env bash
# Open a Lavish artifact and print its loopback URL after service verification.

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
EXPOSE_SCRIPT="${OPEN_LAVISH_EXPOSE_SCRIPT:-$SCRIPT_DIR/expose-port.sh}"

die() {
    echo "open-lavish: $*" >&2
    exit 1
}

run_lavish() {
    npx -y lavish-axi "$@"
}

probe_health() {
    local body_file="$1"
    local status
    if ! status=$(curl -sS --max-time 5 \
        -H "Host: 127.0.0.1:${LAVISH_PORT}" \
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
    local output
    if [[ "${IS_ON_ONA:-}" == true ]]; then
        if ! output=$(
            unset LAVISH_AXI_ALLOWED_HOSTS
            LAVISH_AXI_HOST=127.0.0.1 \
                LAVISH_AXI_LINK_HOST=127.0.0.1 \
                LAVISH_AXI_NO_OPEN=1 \
                run_lavish "$HTML_FILE" "$@"
        ); then
            die "Lavish failed to open $HTML_FILE."
        fi
    elif ! output=$(run_lavish "$HTML_FILE" "$@"); then
        die "Lavish failed to open $HTML_FILE."
    fi
    if [[ "${IS_ON_ONA:-}" == true ]]; then
        printf '%s\n' "$output" | sed 's/lavish-axi/lavish-axi-safe/g' >&2
    else
        printf '%s\n' "$output" >&2
    fi
    printf '%s\n' "$output" | sed -n 's/^[[:space:]]*url: "\([^"]*\)"[[:space:]]*$/\1/p' | tail -n 1
}

HEALTH_DIR=""
if [[ "${IS_ON_ONA:-}" == true ]]; then
    exec 8>"$LOCK_FILE"
    flock 8

    HEALTH_DIR=$(mktemp -d)
    trap 'rm -rf "$HEALTH_DIR"' EXIT
    LOCAL_BODY="$HEALTH_DIR/local"
    LOCAL_STATUS=$(probe_health "$LOCAL_BODY")

    if [[ "$LOCAL_STATUS" != unreachable ]]; then
        # Preserve another agent's live review; the next server start uses the loopback-only environment above.
        if [[ "$LOCAL_STATUS" != 2* ]] || ! is_lavish_health "$LOCAL_BODY"; then
            die "port ${LAVISH_PORT} is occupied by a service that is not a healthy Lavish server."
        fi
    fi
fi

LOCAL_URL=$(open_artifact "$@")
[[ -n "$LOCAL_URL" ]] || die "Lavish did not return a session URL."

if [[ "${IS_ON_ONA:-}" == true ]]; then
    FINAL_BODY="$HEALTH_DIR/final"
    FINAL_STATUS=$(probe_health "$FINAL_BODY")
    if [[ "$FINAL_STATUS" != 2* ]] || ! is_lavish_health "$FINAL_BODY"; then
        die "Lavish did not become healthy on loopback after opening (${FINAL_STATUS})."
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
