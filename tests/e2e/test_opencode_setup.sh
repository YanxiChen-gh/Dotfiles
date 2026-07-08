#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-opencode-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/home/custom-config/opencode/plugins"
HOME="$TMP/home"
XDG_CONFIG_HOME="$HOME/custom-config"
EXAMPLE_TOKEN="local-only"
MCP_HOST="example.com"
MCP_CLIENT_ID="client-value"
AGENT_MATURITY_HOME="$HOME/agent-maturity"
HARNESS_HOOKS="$HOME/harness-hooks"
export HOME
export XDG_CONFIG_HOME
export EXAMPLE_TOKEN
export MCP_HOST
export MCP_CLIENT_ID
export AGENT_MATURITY_HOME
export HARNESS_HOOKS
unset MISSING_ENV

mkdir -p "$AGENT_MATURITY_HOME/scripts" "$HARNESS_HOOKS"
cat >"$AGENT_MATURITY_HOME/scripts/scope-gate-userpromptsubmit.sh" <<'EOF'
#!/bin/sh
cat >/dev/null
printf '%s\n' '[scope-gate] test prompt'
EOF
cat >"$AGENT_MATURITY_HOME/scripts/scope-gate-pretooluse.sh" <<'EOF'
#!/bin/sh
input=$(cat)
case "$input" in
  *'src/app.js'*) ;;
  *'/briefs/'*) exit 0 ;;
esac
printf '%s\n' 'scope blocked' >&2
exit 2
EOF
cat >"$HARNESS_HOOKS/comment-self-check.sh" <<'EOF'
#!/bin/sh
cat >/dev/null
printf '%s\n' '{"hookSpecificOutput":{"additionalContext":"Comment self-check test"}}'
EOF
cat >"$HARNESS_HOOKS/verify-gate-pretooluse.sh" <<'EOF'
#!/bin/sh
cat >/dev/null
printf '%s\n' 'Verify gate test block' >&2
exit 2
EOF
cat >"$HARNESS_HOOKS/pr-authoring-gate-pretooluse.sh" <<'EOF'
#!/bin/sh
cat >/dev/null
exit 0
EOF

resolve_script_dir() {
	printf '%s\n' "$ROOT"
}

# shellcheck source=../../install.d/65-opencode.sh
. "$ROOT/install.d/65-opencode.sh"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

CONFIG_DIR="$XDG_CONFIG_HOME/opencode"
printf 'existing config\n' >"$CONFIG_DIR/opencode.jsonc"
printf 'existing legacy config\n' >"$CONFIG_DIR/opencode.json"
printf 'existing rules\n' >"$CONFIG_DIR/AGENTS.md"
printf 'existing plugin\n' >"$CONFIG_DIR/plugins/dotfiles-harness.js"

setup_opencode_config >/dev/null
setup_opencode_config >/dev/null

[ -L "$CONFIG_DIR/opencode.jsonc" ] || fail "config is not linked"
[ -L "$CONFIG_DIR/AGENTS.md" ] || fail "global rules are not linked"
[ -L "$CONFIG_DIR/plugins/dotfiles-harness.js" ] || fail "harness plugin is not linked"
[ "$(cat "$CONFIG_DIR/opencode.jsonc.pre-dotfiles")" = "existing config" ] || fail "config backup is missing"
[ "$(cat "$CONFIG_DIR/opencode.json.pre-dotfiles")" = "existing legacy config" ] || fail "legacy config backup is missing"
[ "$(cat "$CONFIG_DIR/AGENTS.md.pre-dotfiles")" = "existing rules" ] || fail "rules backup is missing"
[ "$(cat "$CONFIG_DIR/plugins/dotfiles-harness.js.pre-dotfiles")" = "existing plugin" ] || fail "plugin backup is missing"

ensure_opencode_path
touch "$HOME/.bash_profile"
ensure_opencode_path
[ "$(grep -cF '.opencode/bin' "$HOME/.profile")" -eq 1 ] || fail "PATH setup is not idempotent"
[ "$(grep -cF '.opencode/bin' "$HOME/.bash_profile")" -eq 1 ] || fail "bash profile PATH setup is missing"

python3 - "$CONFIG_DIR/opencode.jsonc" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    config = json.load(file)

assert config["$schema"] == "https://opencode.ai/config.json"
assert config["model"] == "openai/gpt-5.6-sol"
assert "opencode-claude-auth@1.5.4" in config["plugin"]
for model in config["provider"]["openai"]["models"].values():
    assert "serviceTier" not in model["options"]
    assert model["variants"]["fast"] == {"serviceTier": "priority"}
PY

CLAUDE="$TMP/claude.json"
MCP="$CONFIG_DIR/mcp.json"
cat >"$CLAUDE" <<'EOF'
{
  "mcpServers": {
    "local_server": {
      "type": "stdio",
      "command": "uvx",
      "args": ["example-mcp", "--token", "local-only", "--fallback", "${MISSING_ENV:-fallback-token}"],
      "env": {"EXAMPLE_TOKEN": "local-only"}
    },
    "remote_server": {
      "type": "streamable-http",
      "url": "https://${MCP_HOST:-fallback.example.com}/mcp",
      "headers": {"Authorization": "Bearer local-only"},
      "oauth": {"clientId": "${MCP_CLIENT_ID}", "scopes": "tools:read tools:write"},
      "timeout": 9000
    },
    "unsupported_server": {
      "type": "http",
      "url": "https://example.com/mcp",
      "headersHelper": "get-dynamic-headers"
    }
  }
}
EOF

python3 "$ROOT/scripts/sync_opencode_mcp_from_claude.py" \
	--claude-json "$CLAUDE" \
	--opencode-mcp "$MCP" >/dev/null 2>&1

python3 - "$MCP" <<'PY'
import json
import os
import stat
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as file:
    servers = json.load(file)["mcp"]

assert servers["local_server"] == {
    "type": "local",
    "command": [
        "uvx",
        "example-mcp",
        "--token",
        "{env:EXAMPLE_TOKEN}",
        "--fallback",
        "{env:MISSING_ENV:-fallback-token}",
    ],
    "enabled": True,
    "environment": {"EXAMPLE_TOKEN": "{env:EXAMPLE_TOKEN}"},
}
assert servers["remote_server"] == {
    "type": "remote",
    "url": "https://{env:MCP_HOST:-fallback.example.com}/mcp",
    "enabled": True,
    "headers": {"Authorization": "Bearer {env:EXAMPLE_TOKEN}"},
    "oauth": {
        "clientId": "{env:MCP_CLIENT_ID}",
        "scope": "tools:read tools:write",
    },
    "timeout": 9000,
}
assert "unsupported_server" not in servers
assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
PY

cp "$MCP" "$TMP/mcp-before.json"
chmod 644 "$MCP"
python3 "$ROOT/scripts/sync_opencode_mcp_from_claude.py" \
	--claude-json "$CLAUDE" \
	--opencode-mcp "$MCP" >/dev/null 2>&1
cmp -s "$MCP" "$TMP/mcp-before.json" || fail "MCP sync is not idempotent"
[ "$(stat -c '%a' "$MCP" 2>/dev/null || stat -f '%Lp' "$MCP")" = "600" ] || fail "MCP sync did not restore mode 0600"

node --input-type=module - "$ROOT/opencode/plugins/dotfiles-harness.js" <<'JS'
import assert from "node:assert/strict"
import { spawn as spawnChild } from "node:child_process"
import { Readable } from "node:stream"
import { pathToFileURL } from "node:url"

const spawnedInputs = []
globalThis.Bun = {
  env: process.env,
  spawn(command, options) {
    const child = spawnChild(command[0], command.slice(1), {
      env: options.env,
      stdio: ["pipe", "pipe", "pipe"],
    })
    options.stdin.text().then((input) => {
      spawnedInputs.push({ command, input })
      child.stdin.end(input)
    })
    return {
      stdout: Readable.toWeb(child.stdout),
      stderr: Readable.toWeb(child.stderr),
      exited: new Promise((resolve) => child.on("close", resolve)),
    }
  },
}
const pluginModule = await import(pathToFileURL(process.argv[2]))
const hooks = await pluginModule.DotfilesHarnessPlugin(
  { directory: process.cwd() },
  { hooksDir: process.env.HARNESS_HOOKS },
)
const config = {}
await hooks.config(config)

assert.ok(config.mcp.local_server.command.includes(process.env.EXAMPLE_TOKEN))
assert.equal(config.mcp.local_server.command.at(-1), "fallback-token")
assert.equal(config.mcp.remote_server.url, `https://${process.env.MCP_HOST}/mcp`)
assert.equal(config.mcp.remote_server.oauth.clientId, process.env.MCP_CLIENT_ID)

const system = []
await hooks["experimental.chat.system.transform"]({ sessionID: "test-session" }, { system })
assert.match(system.join("\n"), /scope-gate.*test prompt/)

await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "write", sessionID: "test-session", callID: "write-call" },
    { args: { filePath: "test.js", content: "const value = true" } },
  ),
  /scope blocked/,
)

await hooks["tool.execute.before"](
  { tool: "apply_patch", sessionID: "test-session", callID: "brief-call" },
  {
    args: {
      patchText:
        "*** Begin Patch\n*** Add File: /tmp/data/briefs/test-session.md\n+brief\n*** End Patch",
    },
  },
)

await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "apply_patch", sessionID: "test-session", callID: "mixed-patch-call" },
    {
      args: {
        patchText:
          "*** Begin Patch\n*** Add File: /tmp/data/briefs/test-session.md\n+brief\n*** Update File: src/app.js\n-old\n+new\n*** End Patch",
      },
    },
  ),
  /scope blocked/,
)

const editOutput = { output: "edited" }
await hooks["tool.execute.after"](
  {
    tool: "edit",
    sessionID: "test-session",
    callID: "edit-call",
    args: { filePath: "test.ts", newString: "// explains why" },
  },
  editOutput,
)
assert.ok(
  spawnedInputs.some(({ command, input }) => {
    return command.at(-1).endsWith("comment-self-check.sh") && input.includes("explains why")
  }),
)
assert.match(editOutput.output, /Comment self-check/)

await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "bash", sessionID: "test-session", callID: "bash-call" },
    { args: { command: 'gh -R VantaInc/example pr create --body "missing evidence"' } },
  ),
  /Verify gate/,
)
JS

grep -q "OpenCode Global Instructions" "$CONFIG_DIR/AGENTS.md" || fail "generated rules are missing"

exit 0
