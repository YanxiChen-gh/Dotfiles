#!/bin/sh
# E2E: scripts/sync_cursor_mcp_from_claude.py
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY="$ROOT/scripts/sync_cursor_mcp_from_claude.py"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-mcp-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/.cursor"
CLAUDE="$TMP/.claude.json"
CURSOR="$TMP/.cursor/mcp.json"

assert_py() {
	_python="$1"
	shift
	"$_python" -c "$@"
}

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# --- no .claude.json: no-op, exit 0, no mcp.json created ---
rm -f "$CLAUDE" "$CURSOR"
python3 "$PY" --claude-json "$CLAUDE" --cursor-mcp "$CURSOR" || fail "expected exit 0 when claude json missing"
[ ! -f "$CURSOR" ] || fail "mcp.json should not exist"

# --- stdio + http + empty env stripped ---
cat >"$CLAUDE" <<'EOF'
{
  "mcpServers": {
    "stdio_srv": {
      "type": "stdio",
      "command": "uvx",
      "args": ["langsmith-mcp-server"],
      "env": {}
    },
    "http_srv": {
      "type": "http",
      "url": "https://example.com/mcp"
    }
  }
}
EOF
python3 "$PY" --claude-json "$CLAUDE" --cursor-mcp "$CURSOR" || fail "sync failed"
assert_py python3 "
import json
with open('$CURSOR') as f:
    d = json.load(f)
ms = d['mcpServers']
assert ms['stdio_srv'] == {'command': 'uvx', 'args': ['langsmith-mcp-server']}, ms['stdio_srv']
assert ms['http_srv'] == {'url': 'https://example.com/mcp'}, ms['http_srv']
"

# --- preserves Cursor-only servers ---
cat >"$CURSOR" <<'EOF'
{
  "mcpServers": {
    "cursor_only": {
      "command": "echo",
      "args": ["ok"]
    }
  }
}
EOF
cat >"$CLAUDE" <<'EOF'
{
  "mcpServers": {
    "from_claude": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "some-pkg"]
    }
  }
}
EOF
python3 "$PY" --claude-json "$CLAUDE" --cursor-mcp "$CURSOR" || fail "merge failed"
assert_py python3 "
import json
with open('$CURSOR') as f:
    d = json.load(f)
ms = d['mcpServers']
assert 'cursor_only' in ms and 'from_claude' in ms
assert ms['cursor_only']['command'] == 'echo'
assert ms['from_claude'] == {'command': 'npx', 'args': ['-y', 'some-pkg']}
"

# --- idempotent: second run exit 0, content unchanged ---
cp "$CURSOR" "$TMP/before.json"
python3 "$PY" --claude-json "$CLAUDE" --cursor-mcp "$CURSOR" || fail "idempotent run failed"
cmp -s "$CURSOR" "$TMP/before.json" || fail "mcp.json changed on no-op sync"

# --- update when Claude config changes ---
cat >"$CLAUDE" <<'EOF'
{
  "mcpServers": {
    "from_claude": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "new-version"]
    }
  }
}
EOF
python3 "$PY" --claude-json "$CLAUDE" --cursor-mcp "$CURSOR" || fail "update sync failed"
assert_py python3 "
import json
with open('$CURSOR') as f:
    d = json.load(f)
assert d['mcpServers']['from_claude']['args'] == ['-y', 'new-version']
assert 'cursor_only' in d['mcpServers']
"

# --- invalid JSON -> non-zero exit ---
printf '%s' '{ not json' >"$CLAUDE"
if python3 "$PY" --claude-json "$CLAUDE" --cursor-mcp "$CURSOR"; then
	fail "expected non-zero exit for bad JSON"
fi

exit 0
