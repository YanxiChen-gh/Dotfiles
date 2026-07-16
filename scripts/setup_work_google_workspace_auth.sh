#!/bin/sh
set -eu

required_scopes="https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/presentations,https://www.googleapis.com/auth/drive"
work_domain="vanta.com"

if [ "${WORK_MACHINE:-}" != "1" ]; then
    echo "Google Workspace auth is only available when WORK_MACHINE=1." >&2
    exit 1
fi

if [ -n "${GOOGLE_WORKSPACE_CLI_TOKEN:-}" ] || [ -n "${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE:-}" ]; then
    echo "Unset GOOGLE_WORKSPACE_CLI_TOKEN and GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE before using work auth." >&2
    echo "This helper manages encrypted user OAuth credentials and will not modify external credential sources." >&2
    exit 1
fi

managed_gws="$HOME/.local/bin/gws"
if [ -x "$managed_gws" ]; then
    gws_bin=$managed_gws
elif command -v gws >/dev/null 2>&1; then
    gws_bin=$(command -v gws)
else
    echo "Google Workspace CLI is not installed. Re-run the Dotfiles installer." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 is required to validate Google Workspace authentication." >&2
    exit 1
fi

inspect_auth() {
    status_json=$("$gws_bin" auth status 2>/dev/null || true)
    printf '%s\n' "$status_json" | python3 -c '
import json
import sys

required = {
    "https://www.googleapis.com/auth/documents",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/drive",
}
allowed = required | {
    "openid",
    "email",
    "profile",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
}

try:
    status = json.load(sys.stdin)
except (json.JSONDecodeError, TypeError):
    print("reauth")
    raise SystemExit

if status.get("token_valid") is not True:
    print("reauth")
    raise SystemExit

user = status.get("user")
if not isinstance(user, str) or not user:
    print("reauth")
    raise SystemExit

if not user.lower().endswith("@vanta.com"):
    print("wrong-account")
    raise SystemExit

scopes = status.get("scopes")
if not isinstance(scopes, list):
    print("reauth")
    raise SystemExit

scope_set = set(scopes)
if not required.issubset(scope_set) or not scope_set.issubset(allowed):
    print("reauth")
    raise SystemExit

print("ready")
'
}

auth_state=$(inspect_auth)
if [ "$auth_state" = "ready" ]; then
    echo "Google Workspace authentication is already valid for Docs, Sheets, Slides, and Drive."
    exit 0
fi

if [ "$auth_state" = "wrong-account" ]; then
    "$gws_bin" auth logout >/dev/null 2>&1 || true
    echo "Google Workspace authentication belongs to a non-$work_domain account; credentials were cleared." >&2
    exit 1
fi

if [ -n "${GOOGLE_WORKSPACE_CLI_CLIENT_ID:-}" ] && [ -z "${GOOGLE_WORKSPACE_CLI_CLIENT_SECRET:-}" ]; then
    echo "GOOGLE_WORKSPACE_CLI_CLIENT_SECRET is missing." >&2
    exit 1
fi
if [ -z "${GOOGLE_WORKSPACE_CLI_CLIENT_ID:-}" ] && [ -n "${GOOGLE_WORKSPACE_CLI_CLIENT_SECRET:-}" ]; then
    echo "GOOGLE_WORKSPACE_CLI_CLIENT_ID is missing." >&2
    exit 1
fi

config_dir=${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-"$HOME/.config/gws"}
if [ ! -f "$config_dir/client_secret.json" ] && { [ -z "${GOOGLE_WORKSPACE_CLI_CLIENT_ID:-}" ] || [ -z "${GOOGLE_WORKSPACE_CLI_CLIENT_SECRET:-}" ]; }; then
    echo "No Google Workspace OAuth client is configured." >&2
    echo "Set GOOGLE_WORKSPACE_CLI_CLIENT_ID and GOOGLE_WORKSPACE_CLI_CLIENT_SECRET as work secrets, then retry." >&2
    exit 1
fi

if [ "$auth_state" = "reauth" ]; then
    "$gws_bin" auth logout >/dev/null 2>&1 || true
fi

if [ "${IS_ON_ONA:-}" = "true" ]; then
    echo "Cursor should auto-forward the localhost OAuth callback. If it does not, forward the printed port in the Ports panel before opening the URL."
fi

"$gws_bin" auth login --scopes "$required_scopes"

auth_state=$(inspect_auth)
if [ "$auth_state" != "ready" ]; then
    "$gws_bin" auth logout >/dev/null 2>&1 || true
    echo "Google Workspace authentication did not produce a valid $work_domain token with the required scopes; credentials were cleared." >&2
    exit 1
fi

echo "Google Workspace authentication configured for Docs, Sheets, Slides, and Drive."
