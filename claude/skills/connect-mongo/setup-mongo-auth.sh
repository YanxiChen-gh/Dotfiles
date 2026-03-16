#!/bin/bash
# Setup Tailscale and AWS auth for MongoDB MCP connection
# Run this in your terminal when Claude asks you to authenticate
set -euo pipefail

RST="" RED="" GRN="" YLW="" BLU=""
if test -t 1; then
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if test -n "$ncolors" && test "$ncolors" -ge 8; then
        RST="$(tput sgr0)" RED="$(tput setaf 1)" GRN="$(tput setaf 2)" YLW="$(tput setaf 3)" BLU="$(tput setaf 4)"
    fi
fi

info()  { echo -e "${GRN}[*]${RST} $1"; }
warn()  { echo -e "${YLW}[*]${RST} $1"; }
error() { echo -e "${RED}[!]${RST} $1"; }

PROFILE="${1:-}"
SUBNET="${2:-}"

if [ -z "$PROFILE" ]; then
    echo "Usage: ./setup-mongo-auth.sh <aws-profile> [subnet-router]"
    echo "Example: ./setup-mongo-auth.sh stagingmongoreadonly low-trust"
    exit 1
fi

# 1. Check Tailscale
if [ -n "$SUBNET" ]; then
    info "Checking Tailscale..."
    if tailscale status --self 2>&1 | grep -qi "logged out\|stopped"; then
        warn "Tailscale not connected. Starting..."
        sudo tailscale up --accept-dns --accept-routes
    fi

    # Ensure accept-routes is on
    if tailscale debug prefs 2>&1 | grep -q '"RouteAll": false'; then
        warn "Enabling --accept-routes..."
        sudo tailscale set --accept-routes
    fi

    # Verify subnet router
    if tailscale status --self=false --peers 2>&1 | grep -q "$SUBNET"; then
        info "Subnet router '$SUBNET' is reachable"
    else
        error "Subnet router '$SUBNET' not found in Tailscale peers"
        error "You may need to request access: https://vanta.freshservice.com/support/catalog/items/114"
        exit 1
    fi
else
    info "Skipping Tailscale (not required for this environment)"
fi

# 2. Check AWS auth
info "Checking AWS profile '$PROFILE'..."
if ! aws-vault list --profiles 2>/dev/null | grep -qE "^${PROFILE}$"; then
    error "Profile '$PROFILE' not found in ~/.aws/config"
    error "Update from: https://github.com/VantaInc/obsidian/blob/main/.devcontainer/config_files/aws_config"
    exit 1
fi

info "Authenticating to '$PROFILE' (this may open a browser for SSO)..."
if aws-vault exec "$PROFILE" -- echo "authenticated" 2>&1; then
    info "AWS auth successful"
else
    error "AWS auth failed. Try:"
    error "  1. Sign out: https://vanta.awsapps.com/start#/signout"
    error "  2. Clear cache: aws-vault clear"
    error "  3. Re-run this script"
    exit 1
fi

echo ""
info "All checks passed! Tell Claude you're ready."
