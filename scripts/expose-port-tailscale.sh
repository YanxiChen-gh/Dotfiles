#!/usr/bin/env bash
# Expose a local port to my laptop over the tailnet from an Ona CDE.
#
# Usage: expose-port-tailscale.sh <local-port> [verify-path]
#   expose-port-tailscale.sh 4387 /session/abc123
#
# Handles the full chain: userspace tailscaled (with a SOCKS proxy for
# self-verification), WIF tailnet join, `tailscale serve` on :8080, and an
# end-to-end curl through the tailnet path. The final URL is the only stdout;
# progress and errors go to stderr.
#
# Why always :8080 - tailnet ACLs for tag:ona-dev nodes only admit the port
# the Vanta dev flow uses (NGINX_PORT, 8080). Serving on any other port makes
# the URL hang forever from a laptop while self-tests still pass.

set -euo pipefail

LOCAL_PORT="${1:?usage: expose-port-tailscale.sh <local-port> [verify-path]}"
VERIFY_PATH="${2:-/}"
TAILNET_PORT=8080
SOCKS_PORT=1055
LOCK_FILE="/tmp/expose-port-tailscale-${TAILNET_PORT}.lock"
# Non-sensitive WIF client identifier shared by personal Ona exposure tooling.
TAILSCALE_CLIENT_ID="TJLHJThSEY81CNTRL-kYU8kYS49721CNTRL"
TAILSCALE_AUDIENCE="api.tailscale.com/${TAILSCALE_CLIENT_ID}"

die() {
    echo "[expose-port] $*" >&2
    exit 1
}

validate_hostname() {
    local value="$1"
    if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        die "invalid Ona environment ID $(printf '%q' "$value"); expected one DNS label (1-63 letters, digits, or hyphens, beginning and ending with a letter or digit)."
    fi
}

current_ona_hostname() {
    local environment_output
    local -a environment_ids

    if ! environment_output=$(ona environment get --context environment --field id 2>/dev/null); then
        die "could not derive the current Ona environment ID; check 'ona environment get --context environment --field id'."
    fi
    mapfile -t environment_ids <<<"$environment_output"
    if (( ${#environment_ids[@]} != 1 )) || [[ -z "${environment_ids[0]}" ]]; then
        die "expected exactly one non-empty Ona environment ID from the current environment context."
    fi
    validate_hostname "${environment_ids[0]}"
    printf '%s\n' "${environment_ids[0]}"
}

if [[ "${IS_ON_ONA:-}" != "true" ]]; then
    echo "Not an Ona CDE (IS_ON_ONA != true) - use 'tailscale serve' directly or the editor port-forward." >&2
    exit 1
fi

# 1. tailscaled: userspace networking (no TUN in the CDE). The SOCKS flag is
# what lets this node test its own tailnet URL later - if the daemon is up
# without it, restart it (login state persists in --state; no re-join needed).
if pgrep -x tailscaled >/dev/null \
        && ! (exec 3<>"/dev/tcp/localhost/${SOCKS_PORT}") 2>/dev/null; then
    echo "[expose-port] tailscaled running without SOCKS proxy - restarting it" >&2
    sudo pkill -x tailscaled
    for _ in $(seq 20); do pgrep -x tailscaled >/dev/null || break; sleep 0.5; done
fi
if ! pgrep -x tailscaled >/dev/null; then
    echo "[expose-port] starting tailscaled (userspace networking)..." >&2
    sudo mkdir -p /var/lib/tailscale /var/run/tailscale
    # setsid + stdin redirect: without them the daemon dies with the agent shell
    # The caller intentionally owns this /tmp log.
    # shellcheck disable=SC2024
    sudo setsid tailscaled --tun=userspace-networking \
        --state=/var/lib/tailscale/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock \
        --socks5-server="localhost:${SOCKS_PORT}" \
        >> /tmp/tailscaled.log 2>&1 < /dev/null &
    # ready = daemon answering, even if not yet joined ("Logged out")
    for _ in $(seq 30); do
        tailscale status >/dev/null 2>&1 && break
        tailscale status 2>&1 | grep -q 'Logged out' && break
        sleep 0.5
    done
fi

# 2. Join the tailnet if needed using the current Ona environment ID.
if ! tailscale status --self --peers=false >/dev/null 2>&1; then
    ONA_HOSTNAME=$(current_ona_hostname)
    echo "[expose-port] joining tailnet as ${ONA_HOSTNAME}..." >&2
    sudo tailscale up \
        --client-id="${TAILSCALE_CLIENT_ID}?ephemeral=true&preauthorized=true" \
        --audience="${TAILSCALE_AUDIENCE}" \
        --advertise-tags=tag:ona-dev \
        --hostname="$ONA_HOSTNAME" \
        --accept-dns=false \
        --reset >&2
fi

# 3. Serve. The requested hostname may have been taken (-1 suffix): resolve the
# real FQDN from the daemon (also avoids hardcoding the tailnet domain).
HOST=$(tailscale status --json | jq -re '.Self.DNSName | rtrimstr(".")')

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
    echo "[expose-port] check the app is listening on localhost:${LOCAL_PORT} and 'tailscale serve status'" >&2
    cleanup_changed_mapping
    exit 1
fi

case "${CONTENT_TYPE,,}" in
    text/html*|application/xhtml+xml*)
        if ! OFFENDING_URL=$(python3 - "$RESPONSE_BODY" <<'PY'
from html.parser import HTMLParser
from ipaddress import ip_address
from pathlib import Path
import sys
from urllib.parse import urlparse


class BrowserAssetParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        attribute = "src" if tag == "script" else "href" if tag == "link" else None
        if attribute is None:
            return
        for name, value in attrs:
            if name == attribute and value is not None:
                self.urls.append(value)
                break


parser = BrowserAssetParser()
parser.feed(Path(sys.argv[1]).read_text(errors="replace"))
for url in parser.urls:
    try:
        hostname = urlparse(url).hostname
    except ValueError:
        continue
    if hostname is None:
        continue
    normalized = hostname.rstrip(".").lower()
    if normalized == "localhost":
        print(url)
        break
    try:
        is_loopback = ip_address(normalized).is_loopback
    except ValueError:
        is_loopback = False
    if is_loopback:
        print(url)
        break
PY
        ); then
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
