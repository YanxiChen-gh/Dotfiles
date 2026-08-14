#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
AUTH="$ROOT/scripts/auth-vanta-agents.py"
ENSURE="$ROOT/scripts/ensure_omp_mcp.py"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-auth-vanta-agents-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/state"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    grep -qF -- "$2" "$1" || fail "$1 does not contain $2"
}

create_credential() {
    database=$1
    profile=$2
    mkdir -p "$(dirname "$database")"
    python3 - "$database" "$profile" <<'PY'
import sqlite3
import sys

database, profile = sys.argv[1:]
with sqlite3.connect(database) as connection:
    connection.execute("CREATE TABLE IF NOT EXISTS auth_credentials (provider TEXT, credential_type TEXT, data TEXT, disabled_cause TEXT)")
    connection.execute(
        "INSERT INTO auth_credentials(provider, credential_type, data, disabled_cause) VALUES (?, 'oauth', 'not-read-by-helper', NULL)",
        (f"mcp_oauth:profile:{profile}:https://vanta-be.glean.com/mcp/default",),
    )
PY
}

cat >"$TMP/bin/slack-vanta" <<'EOF'
#!/bin/sh
set -eu
if [ "$1 $2" = "auth status" ]; then
    if [ -f "$AUTH_TEST_STATE/slack" ]; then
        printf '%s\n' 'Authenticated' '  read-only preset: satisfied'
        exit 0
    fi
    printf '%s\n' 'Not authenticated' >&2
    exit 1
fi
if [ "$1 $2" = "auth login" ]; then
    : >"$AUTH_TEST_STATE/slack"
    exit 0
fi
exit 2
EOF

cat >"$TMP/bin/omp" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$AUTH_TEST_STATE/omp.args"
profile=default
while [ "$#" -gt 0 ]; do
    if [ "$1" = "--profile" ]; then profile=$2; shift 2; continue; fi
    shift
done
config_dir=${PI_CONFIG_DIR:-.omp}
case "$config_dir" in
    /*) config_root=$config_dir ;;
    *) config_root=$HOME/$config_dir ;;
esac
if [ "$profile" = default ]; then
    if [ -n "${PI_CODING_AGENT_DIR:-}" ]; then
        database=$PI_CODING_AGENT_DIR/agent.db
    elif [ -n "${XDG_DATA_HOME:-}" ] && [ -d "$XDG_DATA_HOME/omp" ]; then
        database=$XDG_DATA_HOME/omp/agent.db
    else
        database=$config_root/agent/agent.db
    fi
elif [ -n "${XDG_DATA_HOME:-}" ] && [ -d "$XDG_DATA_HOME/omp/profiles/$profile" ]; then
    database=$XDG_DATA_HOME/omp/profiles/$profile/agent.db
else
    database=$config_root/profiles/$profile/agent/agent.db
fi
mkdir -p "$(dirname "$database")"
python3 - "$database" "$profile" <<'PY'
import sqlite3
import sys

database, profile = sys.argv[1:]
with sqlite3.connect(database) as connection:
    connection.execute("CREATE TABLE IF NOT EXISTS auth_credentials (provider TEXT, credential_type TEXT, data TEXT, disabled_cause TEXT)")
    connection.execute(
        "INSERT INTO auth_credentials(provider, credential_type, data, disabled_cause) VALUES (?, 'oauth', 'not-read-by-helper', NULL)",
        (f"mcp_oauth:profile:{profile}:https://vanta-be.glean.com/mcp/default",),
    )
PY
EOF
chmod +x "$TMP/bin/slack-vanta" "$TMP/bin/omp"

HOME="$TMP/home"
PATH="$TMP/bin:$PATH"
AUTH_TEST_STATE="$TMP/state"
PI_CODING_AGENT_DIR="$TMP/home/.omp/agent"
WORK_MACHINE=1
export HOME PATH AUTH_TEST_STATE PI_CODING_AGENT_DIR WORK_MACHINE

if "$AUTH" --status >"$TMP/fresh.out" 2>"$TMP/fresh.err"; then
    fail "fresh status was ready"
fi
assert_contains "$TMP/fresh.out" 'Glean MCP (default profile): missing'
assert_contains "$TMP/fresh.out" 'Vanta Slack CLI: missing'

create_credential "$PI_CODING_AGENT_DIR/agent.db" default
if "$AUTH" --status >"$TMP/glean-only.out" 2>"$TMP/glean-only.err"; then
    fail "Glean-only status was ready"
fi
assert_contains "$TMP/glean-only.out" 'Glean MCP (default profile): ready'
assert_contains "$TMP/glean-only.out" 'Vanta Slack CLI: missing'

: >"$AUTH_TEST_STATE/slack"
"$AUTH" --status >"$TMP/ready.out"
assert_contains "$TMP/ready.out" 'Glean MCP (default profile): ready'
assert_contains "$TMP/ready.out" 'Vanta Slack CLI: ready'

rm -f "$PI_CODING_AGENT_DIR/agent.db"
if "$AUTH" >"$TMP/noninteractive.out" 2>"$TMP/noninteractive.err"; then
    fail "repair accepted non-interactive execution"
fi
assert_contains "$TMP/noninteractive.err" 'private interactive terminal'

printf '%s\n' 'not sqlite' >"$PI_CODING_AGENT_DIR/agent.db"
if "$AUTH" --status >"$TMP/malformed.out" 2>"$TMP/malformed.err"; then
    fail "malformed database was accepted"
fi
assert_contains "$TMP/malformed.err" 'could not inspect OMP credential metadata'

rm -f "$PI_CODING_AGENT_DIR/agent.db" "$AUTH_TEST_STATE/slack"
script -qefc "WORK_MACHINE=1 HOME='$HOME' PATH='$PATH' AUTH_TEST_STATE='$AUTH_TEST_STATE' PI_CODING_AGENT_DIR='$PI_CODING_AGENT_DIR' '$AUTH'" /dev/null >"$TMP/repair.out"
"$AUTH" --status >"$TMP/repaired.out"
assert_contains "$TMP/repaired.out" 'Glean MCP (default profile): ready'
assert_contains "$TMP/repaired.out" 'Vanta Slack CLI: ready'
assert_contains "$AUTH_TEST_STATE/omp.args" '--profile default --no-session'

rm -rf "$HOME/.omp/profiles/team" "$AUTH_TEST_STATE/slack"
OMP_PROFILE=team script -qefc "WORK_MACHINE=1 HOME='$HOME' PATH='$PATH' AUTH_TEST_STATE='$AUTH_TEST_STATE' OMP_PROFILE=team '$AUTH'" /dev/null >"$TMP/profile-repair.out"
OMP_PROFILE=team "$AUTH" --status >"$TMP/profile-status.out"
assert_contains "$TMP/profile-status.out" 'Glean MCP (team profile): ready'
assert_contains "$AUTH_TEST_STATE/omp.args" '--profile team --no-session'

OMP_PROFILE= PI_PROFILE=team "$AUTH" --status >"$TMP/empty-profile-status.out"
assert_contains "$TMP/empty-profile-status.out" 'Glean MCP (default profile): ready'
OMP_PROFILE=team "$AUTH" --profile default --status >"$TMP/default-sentinel-status.out"
assert_contains "$TMP/default-sentinel-status.out" 'Glean MCP (default profile): ready'
if "$AUTH" --profile con.txt --status >"$TMP/invalid-profile.out" 2>"$TMP/invalid-profile.err"; then
    fail "invalid OMP profile was accepted"
fi
assert_contains "$TMP/invalid-profile.err" 'invalid OMP profile'

XDG_DATA_HOME="$TMP/xdg"
mkdir -p "$XDG_DATA_HOME/omp" "$XDG_DATA_HOME/omp/profiles/xdgteam"
create_credential "$XDG_DATA_HOME/omp/agent.db" default
create_credential "$XDG_DATA_HOME/omp/profiles/xdgteam/agent.db" xdgteam
XDG_DATA_HOME="$XDG_DATA_HOME" PI_CODING_AGENT_DIR= "$AUTH" --status >"$TMP/xdg-default-status.out"
assert_contains "$TMP/xdg-default-status.out" 'Glean MCP (default profile): ready'
XDG_DATA_HOME="$XDG_DATA_HOME" OMP_PROFILE=xdgteam "$AUTH" --status >"$TMP/xdg-profile-status.out"
assert_contains "$TMP/xdg-profile-status.out" 'Glean MCP (xdgteam profile): ready'

mkdir -p "$HOME/custom/agent"
create_credential "$HOME/custom/agent/agent.db" default
PI_CONFIG_DIR=custom PI_CODING_AGENT_DIR= XDG_DATA_HOME= "$AUTH" --status >"$TMP/relative-config-status.out"
assert_contains "$TMP/relative-config-status.out" 'Glean MCP (default profile): ready'

if WORK_MACHINE=0 "$AUTH" --status >"$TMP/personal.out" 2>"$TMP/personal.err"; then
    fail "auth helper ran outside a work machine"
fi
assert_contains "$TMP/personal.err" 'only available when WORK_MACHINE=1'

if HOME="$TMP/ensure-profile-home" python3 "$ENSURE" --profile con.txt >"$TMP/ensure-invalid.out" 2>"$TMP/ensure-invalid.err"; then
    fail "OMP MCP setup accepted a reserved profile name"
fi
assert_contains "$TMP/ensure-invalid.err" 'invalid OMP profile'

mkdir -p "$TMP/mcp"
cat >"$TMP/mcp/existing.json" <<'EOF'
{
  "disabledServers": ["other"],
  "mcpServers": {
    "other": {"command": "other-server"}
  }
}
EOF
python3 "$ENSURE" --omp-mcp "$TMP/mcp/existing.json" >/dev/null
python3 - "$TMP/mcp/existing.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    data = json.load(file)
assert data["disabledServers"] == ["other"]
assert data["mcpServers"]["other"] == {"command": "other-server"}
assert data["mcpServers"]["glean_default"]["url"] == "https://vanta-be.glean.com/mcp/default"
PY
python3 "$ENSURE" --omp-mcp "$TMP/mcp/existing.json" --remove >/dev/null
python3 - "$TMP/mcp/existing.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    data = json.load(file)
assert data["disabledServers"] == ["other"]
assert data["mcpServers"] == {"other": {"command": "other-server"}}
PY

cat >"$TMP/mcp/custom-glean.json" <<'EOF'
{"mcpServers":{"glean_default":{"type":"http","url":"https://custom.example.com/mcp"}}}
EOF
cp "$TMP/mcp/custom-glean.json" "$TMP/mcp/custom-glean.before"
python3 "$ENSURE" --omp-mcp "$TMP/mcp/custom-glean.json" --remove >/dev/null
cmp "$TMP/mcp/custom-glean.before" "$TMP/mcp/custom-glean.json" \
    || fail "personal cleanup removed a user-managed Glean definition"
[ "$(stat -c %a "$TMP/mcp/existing.json")" = 600 ] || fail "merged MCP config is not mode 600"

PROFILE_CLEAN_HOME="$TMP/profile-clean-home"
HOME="$PROFILE_CLEAN_HOME" PI_CODING_AGENT_DIR= python3 "$ENSURE" >/dev/null
HOME="$PROFILE_CLEAN_HOME" PI_CODING_AGENT_DIR= python3 "$ENSURE" --profile team >/dev/null
mkdir -p "$PROFILE_CLEAN_HOME/.omp/profiles/custom/agent"
cat >"$PROFILE_CLEAN_HOME/.omp/profiles/custom/agent/mcp.json" <<'EOF'
{"mcpServers":{"glean_default":{"type":"http","url":"https://custom.example.com/mcp"}}}
EOF
HOME="$PROFILE_CLEAN_HOME" PI_CODING_AGENT_DIR= python3 "$ENSURE" --remove-all-profiles >/dev/null
python3 - "$PROFILE_CLEAN_HOME" <<'PY'
import json
from pathlib import Path
import sys

home = Path(sys.argv[1])
with (home / ".omp/agent/mcp.json").open(encoding="utf-8") as file:
    default = json.load(file)
with (home / ".omp/profiles/team/agent/mcp.json").open(encoding="utf-8") as file:
    team = json.load(file)
with (home / ".omp/profiles/custom/agent/mcp.json").open(encoding="utf-8") as file:
    custom = json.load(file)
assert "glean_default" not in default["mcpServers"]
assert "glean_default" not in team["mcpServers"]
assert custom["mcpServers"]["glean_default"]["url"] == "https://custom.example.com/mcp"
PY

cat >"$TMP/mcp/legacy.json" <<'EOF'
{"mcpServers":{"legacy":{"command":"legacy-server"}}}
EOF
ln -s "$TMP/mcp/legacy.json" "$TMP/mcp/managed-link.json"
python3 "$ENSURE" \
    --omp-mcp "$TMP/mcp/managed-link.json" \
    --legacy-managed-path "$TMP/mcp/legacy.json" >/dev/null
[ ! -L "$TMP/mcp/managed-link.json" ] || fail "legacy managed symlink was retained"
python3 - "$TMP/mcp/managed-link.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    data = json.load(file)
assert "legacy" in data["mcpServers"]
assert "glean_default" in data["mcpServers"]
PY

cat >"$TMP/mcp/invalid-legacy.json" <<'EOF'
{"mcpServers":[]}
EOF
ln -s "$TMP/mcp/invalid-legacy.json" "$TMP/mcp/invalid-managed-link.json"
if python3 "$ENSURE" \
    --omp-mcp "$TMP/mcp/invalid-managed-link.json" \
    --legacy-managed-path "$TMP/mcp/invalid-legacy.json" >"$TMP/invalid.out" 2>"$TMP/invalid.err"; then
    fail "invalid legacy MCP config was accepted"
fi
[ -L "$TMP/mcp/invalid-managed-link.json" ] || fail "failed migration removed the legacy symlink"

ln -s "$TMP/mcp/existing.json" "$TMP/mcp/unmanaged-link.json"
if python3 "$ENSURE" \
    --omp-mcp "$TMP/mcp/unmanaged-link.json" \
    --legacy-managed-path "$TMP/mcp/legacy.json" >"$TMP/unmanaged.out" 2>"$TMP/unmanaged.err"; then
    fail "unmanaged MCP symlink was replaced"
fi
assert_contains "$TMP/unmanaged.err" 'refusing to replace unmanaged symlink'

INSTALL_HOME="$TMP/install-home"
(
    HOME="$INSTALL_HOME"
    WORK_MACHINE=0
    export HOME WORK_MACHINE
    . "$ROOT/install.d/10-helpers.sh"
    . "$ROOT/install.d/35-agent-helpers.sh"
    resolve_script_dir() { printf '%s\n' "$ROOT"; }
    setup_agent_helpers
)
[ ! -e "$INSTALL_HOME/.local/bin/auth-vanta-agents" ] || fail "personal setup installed work auth helper"
mkdir -p "$INSTALL_HOME/.local/bin"
printf 'unmanaged helper\n' >"$INSTALL_HOME/.local/bin/auth-vanta-agents"
(
    HOME="$INSTALL_HOME"
    WORK_MACHINE=1
    export HOME WORK_MACHINE
    . "$ROOT/install.d/10-helpers.sh"
    . "$ROOT/install.d/35-agent-helpers.sh"
    resolve_script_dir() { printf '%s\n' "$ROOT"; }
    setup_agent_helpers
)
[ "$(readlink "$INSTALL_HOME/.local/bin/auth-vanta-agents")" = "$AUTH" ] \
    || fail "work setup did not install auth helper"
for target in \
    "$INSTALL_HOME/.claude/skills/auth-vanta-agents" \
    "$INSTALL_HOME/.agents/skills/auth-vanta-agents" \
    "$INSTALL_HOME/.cursor/skills-cursor/auth-vanta-agents"
do
    mkdir -p "$(dirname "$target")"
    ln -s "$ROOT/shared-skills/auth-vanta-agents/" "$target"
done
(
    HOME="$INSTALL_HOME"
    WORK_MACHINE=0
    export HOME WORK_MACHINE
    . "$ROOT/install.d/10-helpers.sh"
    . "$ROOT/install.d/35-agent-helpers.sh"
    resolve_script_dir() { printf '%s\n' "$ROOT"; }
    setup_agent_helpers
)
[ ! -L "$INSTALL_HOME/.local/bin/auth-vanta-agents" ] || fail "personal setup retained work auth helper"
[ "$(cat "$INSTALL_HOME/.local/bin/auth-vanta-agents")" = "unmanaged helper" ] \
    || fail "personal setup did not restore the unmanaged auth helper"
for target in \
    "$INSTALL_HOME/.claude/skills/auth-vanta-agents" \
    "$INSTALL_HOME/.agents/skills/auth-vanta-agents" \
    "$INSTALL_HOME/.cursor/skills-cursor/auth-vanta-agents"
do
    [ ! -e "$target" ] || fail "personal setup retained work auth skill: $target"
done

printf 'auth-vanta-agents e2e passed\n'
