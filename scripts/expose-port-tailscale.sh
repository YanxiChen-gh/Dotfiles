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

# 2. Join the tailnet if needed (WIF; repo script tags tag:ona-dev).
if ! tailscale status --self --peers=false >/dev/null 2>&1; then
    JOIN_SCRIPT="/workspaces/obsidian/scripts/dev/tailscale-up-ona.sh"
    if [[ ! -x "$JOIN_SCRIPT" ]]; then
        echo "[expose-port] join script not found at $JOIN_SCRIPT - join the tailnet manually first." >&2
        exit 1
    fi
    # Default hostname derivation in the script can return every env id; pass one.
    "$JOIN_SCRIPT" "yanxi-$(hostname | tr -cd 'a-zA-Z0-9-' | cut -c1-40)" >&2
fi

# 3. Serve. The requested hostname may have been taken (-1 suffix): resolve the
# real FQDN from the daemon (also avoids hardcoding the tailnet domain).
HOST=$(tailscale status --json | jq -re '.Self.DNSName | rtrimstr(".")')
if sudo tailscale serve status --json 2>/dev/null \
        | jq -e --arg hostport "${HOST}:${TAILNET_PORT}" '.Web[$hostport] != null' >/dev/null; then
    echo "[expose-port] replacing existing :${TAILNET_PORT} mapping (would shadow it otherwise)" >&2
    sudo tailscale serve --http="${TAILNET_PORT}" off >&2
fi
sudo tailscale serve --bg --http="${TAILNET_PORT}" "http://localhost:${LOCAL_PORT}" >&2

URL="http://${HOST}:${TAILNET_PORT}"

# 4. Verify e2e through the tailnet path (DNS + serve + app; ACLs can't be
# self-tested - self-traffic bypasses them, which is why only :8080 is safe).
STATUS=$(curl -s --max-time 15 --proxy "socks5h://localhost:${SOCKS_PORT}" \
    -o /dev/null -w '%{http_code}' "${URL}${VERIFY_PATH}") || STATUS="unreachable"
if [[ "$STATUS" != 2* && "$STATUS" != 3* ]]; then
    echo "[expose-port] verification FAILED (${STATUS}) for ${URL}${VERIFY_PATH}" >&2
    echo "[expose-port] check the app is listening on localhost:${LOCAL_PORT} and 'tailscale serve status'" >&2
    exit 1
fi

echo "[expose-port] verified (${STATUS})." >&2
echo "${URL}${VERIFY_PATH}"
