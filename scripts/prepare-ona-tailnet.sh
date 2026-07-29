#!/usr/bin/env bash
# Ensure an Ona CDE is joined to the tailnet and print its current DNS name.

set -euo pipefail

SOCKS_PORT="${ONA_TAILNET_SOCKS_PORT:-1055}"
LOCK_FILE="${ONA_TAILNET_LOCK_FILE:-/tmp/prepare-ona-tailnet.lock}"
# Non-sensitive WIF client identifier shared by personal Ona exposure tooling.
TAILSCALE_CLIENT_ID="TJLHJThSEY81CNTRL-kYU8kYS49721CNTRL"
TAILSCALE_AUDIENCE="api.tailscale.com/${TAILSCALE_CLIENT_ID}"

die() {
    echo "[ona-tailnet] $*" >&2
    exit 1
}

validate_ona_hostname() {
    local value="$1"
    if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        die "invalid Ona environment ID $(printf '%q' "$value"); expected one DNS label."
    fi
}

current_ona_hostname() {
    local environment_output
    local -a environment_ids

    if ! environment_output=$(ona environment get --context environment --field id 2>/dev/null); then
        die "could not derive the current Ona environment ID."
    fi
    mapfile -t environment_ids <<<"$environment_output"
    if (( ${#environment_ids[@]} != 1 )) || [[ -z "${environment_ids[0]}" ]]; then
        die "expected exactly one non-empty Ona environment ID."
    fi
    validate_ona_hostname "${environment_ids[0]}"
    printf '%s\n' "${environment_ids[0]}"
}

if [[ "${IS_ON_ONA:-}" != true ]]; then
    die "not an Ona CDE (IS_ON_ONA != true)."
fi

exec 9>"$LOCK_FILE"
flock 9

if pgrep -x tailscaled >/dev/null \
        && ! (exec 3<>"/dev/tcp/localhost/${SOCKS_PORT}") 2>/dev/null; then
    echo "[ona-tailnet] tailscaled is missing its SOCKS proxy; restarting it." >&2
    sudo pkill -x tailscaled
    for _ in $(seq 20); do pgrep -x tailscaled >/dev/null || break; sleep 0.5; done
fi

if ! pgrep -x tailscaled >/dev/null; then
    echo "[ona-tailnet] starting tailscaled." >&2
    sudo mkdir -p /var/lib/tailscale /var/run/tailscale
    # shellcheck disable=SC2024
    sudo setsid tailscaled --tun=userspace-networking \
        --state=/var/lib/tailscale/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock \
        --socks5-server="localhost:${SOCKS_PORT}" \
        >> /tmp/tailscaled.log 2>&1 < /dev/null &
    for _ in $(seq 30); do
        tailscale status >/dev/null 2>&1 && break
        tailscale status 2>&1 | grep -q 'Logged out' && break
        sleep 0.5
    done
fi

if ! tailscale status --self --peers=false >/dev/null 2>&1; then
    ONA_HOSTNAME=$(current_ona_hostname)
    echo "[ona-tailnet] joining tailnet as ${ONA_HOSTNAME}." >&2
    sudo tailscale up \
        --client-id="${TAILSCALE_CLIENT_ID}?ephemeral=true&preauthorized=true" \
        --audience="${TAILSCALE_AUDIENCE}" \
        --advertise-tags=tag:ona-dev \
        --hostname="$ONA_HOSTNAME" \
        --accept-dns=false \
        --reset >&2
fi

HOST=$(tailscale status --json | jq -re '.Self.DNSName | rtrimstr(".")')
if [[ ! "$HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    die "tailscaled returned an invalid DNS name."
fi
printf '%s\n' "$HOST"
