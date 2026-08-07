#!/usr/bin/env bash
# Expose a local port to my laptop over the tailnet from an Ona CDE.
#
# Usage: expose-port-tailscale.sh <local-port> [verify-path]
#   expose-port-tailscale.sh 4387 /session/abc123
#
# Prepares the shared Ona tailnet connection, configures `tailscale serve` on
# :8080, and verifies the URL through the tailnet path. The final URL is the
# only stdout; progress and errors go to stderr.
#
# Why always :8080 - tailnet ACLs for tag:ona-dev nodes only admit the port
# the Vanta dev flow uses (NGINX_PORT, 8080). Serving on any other port makes
# the URL hang forever from a laptop while self-tests still pass.

set -euo pipefail

LOCAL_PORT="${1:?usage: expose-port-tailscale.sh <local-port> [verify-path]}"
VERIFY_PATH="${2:-/}"
TAILNET_PORT=8080
SOCKS_PORT="${ONA_TAILNET_SOCKS_PORT:-1055}"
LOCK_FILE="/tmp/expose-port-tailscale-${TAILNET_PORT}.lock"

if [[ "${IS_ON_ONA:-}" != "true" ]]; then
    echo "Not an Ona CDE (IS_ON_ONA != true) - use 'tailscale serve' directly or the editor port-forward." >&2
    exit 1
fi

# The helper serializes daemon repair, WIF join, and DNS-name resolution across
# agents before this script takes the separate Serve-mapping lock.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREPARE_SCRIPT="${PREPARE_ONA_TAILNET_SCRIPT:-$SCRIPT_DIR/prepare-ona-tailnet.sh}"
BROWSER_ASSET_CHECKER="${BROWSER_ASSET_CHECKER:-$SCRIPT_DIR/find-loopback-browser-asset.py}"
if [[ ! -x "$PREPARE_SCRIPT" ]]; then
    echo "[expose-port] Ona tailnet helper is not executable: $PREPARE_SCRIPT" >&2
    exit 1
fi
HOST=$($PREPARE_SCRIPT)

# Only one ACL-permitted port is available, so helper invocations must not evict
# each other's live mappings.
exec 9>"$LOCK_FILE"
flock 9

if ! SERVE_STATUS=$(sudo tailscale serve status --json 2>/dev/null); then
    echo "[expose-port] could not read the existing Tailscale Serve mapping; refusing to replace it." >&2
    exit 1
fi
if ! jq -e 'type == "object"' >/dev/null <<<"$SERVE_STATUS"; then
    echo "[expose-port] existing Tailscale Serve status is invalid; refusing to replace it." >&2
    exit 1
fi

TARGET="http://localhost:${LOCAL_PORT}"
CURRENT_TARGET=$(jq -r --arg hostport "${HOST}:${TAILNET_PORT}" \
    '.Web[$hostport].Handlers["/"].Proxy // empty' <<<"$SERVE_STATUS")
MAPPING_CHANGED=false

unrelated_handler_count() {
    local status="$1"
    local current_target="$2"

    jq -r \
        --arg hostport "${HOST}:${TAILNET_PORT}" \
        --arg port "$TAILNET_PORT" \
        --arg port_suffix ":${TAILNET_PORT}" \
        --arg current_target "$current_target" \
        '[
            (.Web // {} | to_entries[] | select(.key != $hostport and (.key | endswith($port_suffix))) | .key),
            (.Web[$hostport].Handlers // {} | to_entries[] | select(.key != "/" or (.value.Proxy // "") != $current_target) | .key),
            (.TCP[$port] // empty | select($current_target == "") | $port),
            (.Foreground // {} | to_entries[] | .value |
                (.TCP // {} | keys[] | select(. == $port)),
                (.Web // {} | keys[] | select(endswith($port_suffix)))),
            (.Services // {} | to_entries[] | .value |
                (.TCP // {} | keys[] | select(. == $port)),
                (.Web // {} | keys[] | select(endswith($port_suffix))))
        ] | length' <<<"$status"
}

UNRELATED_HANDLER_COUNT=$(unrelated_handler_count "$SERVE_STATUS" "$CURRENT_TARGET")

if [[ "$UNRELATED_HANDLER_COUNT" != 0 ]]; then
    echo "[expose-port] :${TAILNET_PORT} has unrelated Serve handlers; refusing to replace them." >&2
    exit 1
fi

cleanup_changed_mapping() {
    if [[ "$MAPPING_CHANGED" != true ]]; then
        return
    fi
    local cleanup_status
    local cleanup_target
    local cleanup_unrelated_count

    if ! cleanup_status=$(sudo tailscale serve status --json 2>/dev/null); then
        echo "[expose-port] cleanup skipped because the current Serve mapping could not be read." >&2
        return
    fi
    cleanup_target=$(jq -r --arg hostport "${HOST}:${TAILNET_PORT}" \
        '.Web[$hostport].Handlers["/"].Proxy // empty' <<<"$cleanup_status")
    cleanup_unrelated_count=$(unrelated_handler_count "$cleanup_status" "$cleanup_target")
    if [[ "$cleanup_target" != "$TARGET" || "$cleanup_unrelated_count" != 0 ]]; then
        echo "[expose-port] cleanup skipped because :${TAILNET_PORT} is no longer exclusively owned by this invocation." >&2
        return
    fi
    if ! sudo tailscale serve --http="${TAILNET_PORT}" off >&2; then
        echo "[expose-port] cleanup FAILED; remove the invalid mapping with 'sudo tailscale serve --http=${TAILNET_PORT} off'." >&2
    fi
}

if [[ -n "$CURRENT_TARGET" && "$CURRENT_TARGET" != "$TARGET" ]]; then
    if [[ "$CURRENT_TARGET" =~ ^http://localhost:([0-9]+)$ ]]; then
        CURRENT_PORT="${BASH_REMATCH[1]}"
        if (exec 3<>"/dev/tcp/localhost/${CURRENT_PORT}") 2>/dev/null; then
            echo "[expose-port] :${TAILNET_PORT} already exposes live target ${CURRENT_TARGET}; refusing to break its URL." >&2
            echo "[expose-port] use an editor port-forward for localhost:${LOCAL_PORT}, or stop the existing exposure first." >&2
            exit 1
        fi
    else
        echo "[expose-port] :${TAILNET_PORT} has unsupported target ${CURRENT_TARGET}; refusing to replace it." >&2
        exit 1
    fi

    echo "[expose-port] replacing stale :${TAILNET_PORT} mapping (${CURRENT_TARGET})" >&2
    if ! sudo tailscale serve --http="${TAILNET_PORT}" off >&2; then
        exit 1
    fi
fi

if [[ "$CURRENT_TARGET" != "$TARGET" ]]; then
    if ! sudo tailscale serve --bg --http="${TAILNET_PORT}" "$TARGET" >&2; then
        exit 1
    fi
    MAPPING_CHANGED=true
fi

URL="http://${HOST}:${TAILNET_PORT}"

# 4. Verify e2e through the tailnet path (DNS + serve + app; ACLs can't be
# self-tested - self-traffic bypasses them, which is why only :8080 is safe).
VERIFY_TMP=$(mktemp -d)
trap 'rm -rf "$VERIFY_TMP"' EXIT
RESPONSE_BODY="$VERIFY_TMP/body"
if CURL_META=$(curl -s --show-error --location --max-time 15 \
    --proxy "socks5h://localhost:${SOCKS_PORT}" \
    -o "$RESPONSE_BODY" -w $'%{http_code}\n%{content_type}' "${URL}${VERIFY_PATH}"); then
    STATUS=${CURL_META%%$'\n'*}
    CONTENT_TYPE=${CURL_META#*$'\n'}
else
    STATUS="unreachable"
    CONTENT_TYPE=""
fi
if [[ "$STATUS" != 2* && "$STATUS" != 3* ]]; then
    echo "[expose-port] verification FAILED (${STATUS}) for ${URL}${VERIFY_PATH}" >&2
    if [[ "$STATUS" == 403 ]] \
            && jq -e '.error == "forbidden host"' "$RESPONSE_BODY" >/dev/null 2>&1; then
        echo "[expose-port] Lavish rejected the tailnet hostname; open the artifact with 'open-lavish' so its startup allowlist is configured." >&2
    else
        echo "[expose-port] check the app is listening on localhost:${LOCAL_PORT} and 'tailscale serve status'" >&2
    fi
    cleanup_changed_mapping
    exit 1
fi

case "${CONTENT_TYPE,,}" in
    text/html*|application/xhtml+xml*)
        if ! OFFENDING_URL=$(python3 "$BROWSER_ASSET_CHECKER" "$RESPONSE_BODY"); then
            echo "[expose-port] could not inspect the verified HTML response." >&2
            cleanup_changed_mapping
            exit 1
        fi
        if [[ -n "$OFFENDING_URL" ]]; then
            echo "[expose-port] verification FAILED: browser-active asset uses CDE loopback: ${OFFENDING_URL}" >&2
            cleanup_changed_mapping
            exit 1
        fi
        ;;
esac

echo "[expose-port] verified (${STATUS})." >&2
echo "${URL}${VERIFY_PATH}"
