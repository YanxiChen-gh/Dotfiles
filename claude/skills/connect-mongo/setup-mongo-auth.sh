#!/bin/bash
# Setup Tailscale and AWS auth for MongoDB MCP connection
# Run this in your terminal when Claude asks you to authenticate
# Writes temporary AWS credentials to /tmp/mongo-aws-creds.json
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
CREDS_FILE="/tmp/mongo-aws-creds.json"

if [ -z "$PROFILE" ]; then
    echo "Usage: ./setup-mongo-auth.sh <aws-profile>"
    echo "Example: ./setup-mongo-auth.sh stagingmongoreadonly"
    exit 1
fi

# 1. Setup Tailscale
info "Setting up Tailscale..."
sudo tailscale up --accept-dns --accept-routes

# 2. Check AWS profile exists
info "Checking AWS profile '$PROFILE'..."
if ! aws-vault list --profiles 2>/dev/null | grep -qE "^${PROFILE}$"; then
    error "Profile '$PROFILE' not found in ~/.aws/config"
    error "Update from: https://github.com/VantaInc/obsidian/blob/main/.devcontainer/config_files/aws_config"
    exit 1
fi

# 3. Authenticate first (allows SSO browser to open)
info "Authenticating to '$PROFILE' (this may open a browser for SSO)..."
if ! aws-vault exec "$PROFILE" -- echo "authenticated"; then
    error "AWS auth failed. Try:"
    error "  1. Sign out: https://vanta.awsapps.com/start#/signout"
    error "  2. Clear cache: aws-vault clear"
    error "  3. Re-run this script"
    exit 1
fi
info "AWS auth successful"

# 4. Export credentials (session is now cached, no browser needed)
info "Exporting credentials..."
CREDS=$(aws-vault exec "$PROFILE" -- env) || {
    error "Failed to export credentials"
    exit 1
}

ACCESS_KEY=$(echo "$CREDS" | grep '^AWS_ACCESS_KEY_ID=' | cut -d= -f2)
SECRET_KEY=$(echo "$CREDS" | grep '^AWS_SECRET_ACCESS_KEY=' | cut -d= -f2)
SESSION_TOKEN=$(echo "$CREDS" | grep '^AWS_SESSION_TOKEN=' | cut -d= -f2)

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ] || [ -z "$SESSION_TOKEN" ]; then
    error "Failed to extract AWS credentials"
    exit 1
fi

# 5. Write credentials to temp file (readable only by current user)
cat > "$CREDS_FILE" <<EOF
{
  "accessKeyId": "$ACCESS_KEY",
  "secretAccessKey": "$SECRET_KEY",
  "sessionToken": "$SESSION_TOKEN",
  "profile": "$PROFILE"
}
EOF
chmod 600 "$CREDS_FILE"

info "AWS credentials written to $CREDS_FILE"
info "Credentials expire in ~1 hour. Re-run this script to refresh."
echo ""
info "All checks passed! Tell Claude you're ready."
