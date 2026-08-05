#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-opencode-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/home/custom-config/opencode/plugins" "$TMP/home/.opencode/bin"
HOME="$TMP/home"
XDG_CONFIG_HOME="$HOME/custom-config"
OPENCODE_PRIMARY="$TMP/opencode-repo"
OPENCODE_LINKED="$TMP/opencode-linked"
OPENCODE_POOL="$TMP/treehouse-pool/7/opencode-repo"
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
export OPENCODE_PRIMARY OPENCODE_LINKED OPENCODE_POOL
unset MISSING_ENV
unset HERDR_ENV HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_BIN_PATH DOTFILES_HERDR_TASK_WORKSPACE

OPENCODE_ARGS_LOG="$TMP/opencode-args.log"
OPENCODE_START_LOG="$TMP/opencode-start.log"
OPENCODE_ENV_LOG="$TMP/opencode-env.log"
export OPENCODE_ARGS_LOG OPENCODE_START_LOG OPENCODE_ENV_LOG
cat >"$HOME/.opencode/bin/opencode" <<'EOF'
#!/bin/sh
printf '%s\0' "$@" >>"$OPENCODE_ARGS_LOG"
printf '%s\n' "${OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS:-unset}" >>"$OPENCODE_ENV_LOG"
python3 - "$OPENCODE_START_LOG" <<'PY'
import sys
import time

with open(sys.argv[1], "a", encoding="utf-8") as log:
    log.write(f"{time.time()}\n")
PY
EOF
chmod +x "$HOME/.opencode/bin/opencode"

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
  *'"session_id":"approved-root"'*) exit 0 ;;
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

HERDR_TITLE_LOG="$TMP/herdr-title.log"
HERDR_COMMAND_LOG="$TMP/herdr-command.log"
HERDR_FAIL_MARKER="$TMP/herdr-title-failed"
HERDR_TEST_BIN="$TMP/herdr"
export HERDR_TITLE_LOG HERDR_COMMAND_LOG HERDR_FAIL_MARKER HERDR_TEST_BIN
cat >"$HERDR_TEST_BIN" <<'EOF'
#!/bin/sh
if [ "$1 $2 $3" = "integration install opencode" ]; then
    plugin="$HOME/.config/opencode/plugins/herdr-agent-state.js"
    mkdir -p "$(dirname "$plugin")"
    printf '%s\n' '// managed by herdr' >"$plugin"
fi
if [ "$2" != "report-metadata" ]; then
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$HERDR_TITLE_LOG"
fi
printf '%s\n' "$*" >>"$HERDR_COMMAND_LOG"
if [ -n "${HERDR_FAIL_METADATA_ONCE:-}" ] && [ "$1 $2" = "workspace report-metadata" ] && [ ! -e "$HERDR_FAIL_MARKER" ]; then
    : >"$HERDR_FAIL_MARKER"
    exit 7
fi
if [ -n "${HERDR_FAIL_PANE_METADATA_ONCE:-}" ] && [ "$1 $2" = "pane report-metadata" ] && [ ! -e "$HERDR_FAIL_MARKER" ]; then
    : >"$HERDR_FAIL_MARKER"
    exit 7
fi
if [ -n "${HERDR_FAIL_ONCE:-}" ] && [ ! -e "$HERDR_FAIL_MARKER" ]; then
    : >"$HERDR_FAIL_MARKER"
    exit 7
fi
EOF
chmod +x "$HERDR_TEST_BIN"

mkdir -p "$OPENCODE_PRIMARY" "${OPENCODE_POOL%/*}"
git -C "$OPENCODE_PRIMARY" init -q
git -C "$OPENCODE_PRIMARY" config user.name test
git -C "$OPENCODE_PRIMARY" config user.email test@example.com
printf 'fixture\n' >"$OPENCODE_PRIMARY/fixture.txt"
git -C "$OPENCODE_PRIMARY" add fixture.txt
git -C "$OPENCODE_PRIMARY" commit -qm fixture
git -C "$OPENCODE_PRIMARY" worktree add --detach "$OPENCODE_LINKED" >/dev/null
git -C "$OPENCODE_PRIMARY" worktree add --detach "$OPENCODE_POOL" >/dev/null

resolve_script_dir() {
	printf '%s\n' "$ROOT"
}

# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/65-opencode.sh
. "$ROOT/install.d/65-opencode.sh"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

CONFIG_DIR="$XDG_CONFIG_HOME/opencode"
printf 'existing config\n' >"$CONFIG_DIR/opencode.jsonc"
printf 'existing legacy config\n' >"$CONFIG_DIR/opencode.json"
printf 'existing TUI config\n' >"$CONFIG_DIR/tui.jsonc"
printf 'existing legacy TUI config\n' >"$CONFIG_DIR/tui.json"
printf 'existing rules\n' >"$CONFIG_DIR/AGENTS.md"
printf 'existing plugin\n' >"$CONFIG_DIR/plugins/dotfiles-harness.js"

setup_opencode_config >/dev/null
setup_opencode_config >/dev/null
ORIGINAL_PATH=$PATH
HERDR_INSTALL_DIR=$TMP
PATH=/usr/bin:/bin
export HERDR_INSTALL_DIR PATH
install_herdr_opencode_integration >/dev/null
install_herdr_opencode_integration >/dev/null
PATH=$ORIGINAL_PATH
unset HERDR_INSTALL_DIR
export PATH

[ -L "$CONFIG_DIR/opencode.jsonc" ] || fail "config is not linked"
[ -L "$CONFIG_DIR/tui.jsonc" ] || fail "TUI config is not linked"
[ -L "$CONFIG_DIR/AGENTS.md" ] || fail "global rules are not linked"
[ -L "$CONFIG_DIR/plugins/dotfiles-harness.js" ] || fail "harness plugin is not linked"
[ -L "$HOME/.local/bin/opencode" ] || fail "OpenCode wrapper is not linked"
[ "$(readlink "$HOME/.local/bin/opencode")" = "$ROOT/opencode/opencode" ] || fail "OpenCode wrapper links to the wrong source"
[ -L "$CONFIG_DIR/plugins/herdr-agent-state.js" ] || fail "Herdr plugin is not linked into the custom XDG config"
[ "$(readlink "$CONFIG_DIR/plugins/herdr-agent-state.js")" = "$HOME/.config/opencode/plugins/herdr-agent-state.js" ] || fail "Herdr plugin links to the wrong source"
[ "$(grep -cF 'integration' "$HERDR_TITLE_LOG")" -eq 2 ] || fail "Herdr integration installer was not repeatable"
[ "$(cat "$CONFIG_DIR/opencode.jsonc.pre-dotfiles")" = "existing config" ] || fail "config backup is missing"
[ "$(cat "$CONFIG_DIR/opencode.json.pre-dotfiles")" = "existing legacy config" ] || fail "legacy config backup is missing"
[ "$(cat "$CONFIG_DIR/tui.jsonc.pre-dotfiles")" = "existing TUI config" ] || fail "TUI config backup is missing"
[ "$(cat "$CONFIG_DIR/tui.json.pre-dotfiles")" = "existing legacy TUI config" ] || fail "legacy TUI config backup is missing"
[ "$(cat "$CONFIG_DIR/AGENTS.md.pre-dotfiles")" = "existing rules" ] || fail "rules backup is missing"
[ "$(cat "$CONFIG_DIR/plugins/dotfiles-harness.js.pre-dotfiles")" = "existing plugin" ] || fail "plugin backup is missing"

ensure_opencode_path
touch "$HOME/.bash_profile"
ensure_opencode_path
[ "$(grep -cF '.opencode/bin' "$HOME/.profile")" -eq 1 ] || fail "PATH setup is not idempotent"
[ "$(grep -cF '.opencode/bin' "$HOME/.bash_profile")" -eq 1 ] || fail "bash profile PATH setup is missing"
grep -qFx 'export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"' "$HOME/.profile" || fail "wrapper does not precede the real OpenCode binary"

if command -v zsh >/dev/null 2>&1; then
    mkdir -p "$HOME/.oh-my-zsh" "$HOME/.nvm/versions/node/test/bin"
    : >"$HOME/.oh-my-zsh/oh-my-zsh.sh"
    cat >"$HOME/.antigen.zsh" <<'EOF'
antigen() { :; }
EOF
    cat >"$HOME/.nvm/nvm.sh" <<'EOF'
nvm() { :; }
export NVM_BIN="$HOME/.nvm/versions/node/test/bin"
export PATH="$NVM_BIN:$PATH"
EOF
    : >"$HOME/.nvm/bash_completion"
    cat >"$HOME/.nvm/versions/node/test/bin/node" <<'EOF'
#!/bin/sh
exit 0
EOF
    cat >"$HOME/.nvm/versions/node/test/bin/opencode" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$HOME/.nvm/versions/node/test/bin/node" "$HOME/.nvm/versions/node/test/bin/opencode"
    ln -s "$ROOT/.zshrc" "$HOME/.zshrc"

    resolved_opencode=$(ZDOTDIR="$HOME" zsh -dlic 'command -v opencode')
    [ "$resolved_opencode" = "$HOME/.local/bin/opencode" ] || fail "clean zsh resolved OpenCode to $resolved_opencode"
    resolved_node=$(ZDOTDIR="$HOME" zsh -dlic 'command -v node')
    [ "$resolved_node" = "$HOME/.nvm/versions/node/test/bin/node" ] || fail "clean zsh did not preserve NVM Node resolution"
    opencode_locations=$(ZDOTDIR="$HOME" zsh -dlic 'type -a opencode')
    case "$opencode_locations" in
        *"$HOME/.local/bin/opencode"*"$HOME/.opencode/bin/opencode"*"$HOME/.nvm/versions/node/test/bin/opencode"*) ;;
        *) fail "clean zsh did not retain the wrapper, real binary, and NVM installation" ;;
    esac
fi

assert_opencode_args() {
    expected=$1
    shift
    : >"$OPENCODE_ARGS_LOG"
    "$HOME/.local/bin/opencode" "$@"
    python3 - "$OPENCODE_ARGS_LOG" "$expected" <<'PY'
import sys

with open(sys.argv[1], "rb") as log:
    actual = [value.decode() for value in log.read().split(b"\0") if value]
expected = sys.argv[2].split("|") if sys.argv[2] else []
if actual != expected:
    raise SystemExit(f"OpenCode arguments were {actual!r}, expected {expected!r}")
PY
}

assert_opencode_args '--auto'
assert_opencode_args '--auto|--session|test-session' --session test-session
assert_opencode_args '--auto|--session|test-session' --auto --session test-session
assert_opencode_args 'run|--auto|hello' run hello
assert_opencode_args 'run|hello|--auto' run hello --auto
assert_opencode_args 'debug|paths' debug paths
assert_opencode_args '--auto|--version' --version

: >"$OPENCODE_ENV_LOG"
unset OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS
"$HOME/.local/bin/opencode" debug paths
[ "$(cat "$OPENCODE_ENV_LOG")" = "true" ] || fail "background subagents are not enabled by default"

: >"$OPENCODE_ENV_LOG"
OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=false "$HOME/.local/bin/opencode" debug paths
[ "$(cat "$OPENCODE_ENV_LOG")" = "false" ] || fail "background subagent override was not preserved"

: >"$OPENCODE_START_LOG"
rm -f "$TMP/opencode-resume-stagger"
HERDR_ENV=1 OPENCODE_RESUME_STAGGER_SECONDS=0.2 OPENCODE_RESUME_STAGGER_STATE="$TMP/opencode-resume-stagger" \
    "$HOME/.local/bin/opencode" --session first &
first_resume=$!
HERDR_ENV=1 OPENCODE_RESUME_STAGGER_SECONDS=0.2 OPENCODE_RESUME_STAGGER_STATE="$TMP/opencode-resume-stagger" \
    "$HOME/.local/bin/opencode" --session second &
second_resume=$!
wait "$first_resume" "$second_resume"
python3 - "$OPENCODE_START_LOG" <<'PY'
import sys

with open(sys.argv[1], encoding="utf-8") as log:
    starts = sorted(float(value) for value in log if value.strip())
if len(starts) != 2 or starts[1] - starts[0] < 0.15:
    raise SystemExit(f"restored OpenCode starts were not staggered: {starts!r}")
PY

python3 - "$CONFIG_DIR/opencode.jsonc" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    config = json.load(file)

assert config["$schema"] == "https://opencode.ai/config.json"
assert config["model"] == "openai/gpt-5.6-sol"
assert config["agent"]["build"]["variant"] == "high"
assert config["agent"]["plan"]["variant"] == "high"
assert config["agent"]["general"]["variant"] == "high"
assert config["agent"]["explore"]["variant"] == "medium"
assert "opencode-claude-auth@1.5.4" in config["plugin"]
assert "provider" not in config
PY

python3 - "$CONFIG_DIR/tui.jsonc" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    config = json.load(file)

assert config["$schema"] == "https://opencode.ai/tui.json"
assert config["attention"] == {
    "enabled": True,
    "notifications": True,
    "sound": False,
}
PY

python3 - "$ROOT/herdr/config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as file:
    config = tomllib.load(file)

assert config["ui"]["sidebar"]["agents"]["rows_by_agent"]["opencode"] == [
    ["state_icon", "workspace", "tab"],
    ["agent"],
    ["$subagent_1"],
    ["$subagent_2"],
    ["$subagent_3"],
    ["$subagent_summary"],
]
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
    "glean_default": {
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

cat >"$MCP" <<'EOF'
{
  "mcp": {
    "stale_server": {
      "enabled": false
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

assert servers == {"glean_default": {
    "type": "remote",
    "url": "https://{env:MCP_HOST:-fallback.example.com}/mcp",
    "enabled": True,
    "headers": {"Authorization": "Bearer {env:EXAMPLE_TOKEN}"},
    "oauth": {
        "clientId": "{env:MCP_CLIENT_ID}",
        "scope": "tools:read tools:write",
    },
    "timeout": 9000,
}}
assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
PY

python3 - "$MCP.pre-authoritative-sync" <<'PY'
import json
import os
import stat
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as file:
    assert "stale_server" in json.load(file)["mcp"]
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
import { readFile, rm, writeFile } from "node:fs/promises"
import { Readable } from "node:stream"
import { pathToFileURL } from "node:url"

const spawnedInputs = []
globalThis.Bun = {
  env: process.env,
  spawn(command, options) {
    const child = spawnChild(command[0], command.slice(1), {
      env: options.env,
      stdio: [options.stdin === "ignore" ? "ignore" : "pipe", options.stdout, options.stderr],
    })
    if (options.stdin instanceof Blob) {
      options.stdin.text().then((input) => {
        spawnedInputs.push({ command, input })
        child.stdin.end(input)
      })
    }
    return {
      stdout: child.stdout && Readable.toWeb(child.stdout),
      stderr: child.stderr && Readable.toWeb(child.stderr),
      exited: new Promise((resolve) => child.on("close", resolve)),
    }
  },
}
const pluginModule = await import(pathToFileURL(process.argv[2]))
const sessionRecords = new Map([["test-session", { id: "test-session" }]])
const client = {
  session: {
    async get({ path }) {
      return { data: sessionRecords.get(path.id) }
    },
  },
}
const hooks = await pluginModule.DotfilesHarnessPlugin(
  { client, directory: process.cwd() },
  { hooksDir: process.env.HARNESS_HOOKS },
)
const config = {}
await hooks.config(config)

assert.deepEqual(Object.keys(config.mcp), ["glean_default"])
assert.equal(config.mcp.glean_default.url, `https://${process.env.MCP_HOST}/mcp`)
assert.equal(config.mcp.glean_default.headers.Authorization, `Bearer ${process.env.EXAMPLE_TOKEN}`)
assert.equal(config.mcp.glean_default.oauth.clientId, process.env.MCP_CLIENT_ID)

const system = []
await hooks["experimental.chat.system.transform"]({ sessionID: "test-session" }, { system })
assert.match(system.join("\n"), /scope-gate.*test prompt/)

const sessionEvent = (type, info) => ({ event: { type, properties: { info } } })
void hooks.event(sessionEvent("session.created", { id: "approved-root" }))
void hooks.event(
  sessionEvent("session.created", {
    id: "approved-child",
    parentID: "approved-root",
  }),
)
void hooks.event(
  sessionEvent("session.created", {
    id: "approved-grandchild",
    parentID: "approved-child",
  }),
)

const childSystem = []
await hooks["experimental.chat.system.transform"](
  { sessionID: "approved-child" },
  { system: childSystem },
)
assert.doesNotMatch(childSystem.join("\n"), /scope-gate.*test prompt/)
assert.match(childSystem.join("\n"), /Do not launch Lavish/)

await hooks["tool.execute.before"](
  { tool: "write", sessionID: "approved-grandchild", callID: "child-write-call" },
  { args: { filePath: "src/app.js", content: "const value = true" } },
)
assert.ok(
  spawnedInputs.some(({ command, input }) => {
    return (
      command.at(-1).endsWith("scope-gate-pretooluse.sh") &&
      input.includes('"session_id":"approved-root"')
    )
  }),
)

void hooks.event(sessionEvent("session.created", { id: "unapproved-root" }))
void hooks.event(
  sessionEvent("session.created", {
    id: "unapproved-child",
    parentID: "unapproved-root",
  }),
)
await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "write", sessionID: "unapproved-child", callID: "blocked-child-write-call" },
    { args: { filePath: "src/app.js", content: "const value = true" } },
  ),
  (error) => {
    assert.match(error.message, /return this blocker to the parent/)
    assert.doesNotMatch(error.message, /scope-gate|Lavish/)
    return true
  },
)

await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "question", sessionID: "approved-child", callID: "child-question-call" },
    { args: {} },
  ),
  /return questions to their parent/,
)
await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "bash", sessionID: "approved-child", callID: "child-lavish-call" },
    { args: { command: "bash -lc 'npx -y lavish-axi /tmp/review.html'" } },
  ),
  /must not launch Lavish/,
)
await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "bash", sessionID: "approved-child", callID: "child-lavish-substitution-call" },
    { args: { command: "result=$(npx -y lavish-axi /tmp/review.html)" } },
  ),
  /must not launch Lavish/,
)
await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "bash", sessionID: "approved-child", callID: "child-lavish-chain-call" },
    { args: { command: "command -v lavish-axi && lavish-axi /tmp/review.html" } },
  ),
  /must not launch Lavish/,
)
await hooks["tool.execute.before"](
  { tool: "question", sessionID: "test-session", callID: "root-question-call" },
  { args: {} },
)
sessionRecords.set("resumed-grandchild", {
  id: "resumed-grandchild",
  parentID: "resumed-child",
})
sessionRecords.set("resumed-child", {
  id: "resumed-child",
  parentID: "approved-root",
})
sessionRecords.set("approved-root", { id: "approved-root" })
const resumedChildSystem = []
await hooks["experimental.chat.system.transform"](
  { sessionID: "resumed-grandchild" },
  { system: resumedChildSystem },
)
assert.match(resumedChildSystem.join("\n"), /Do not launch Lavish/)
await hooks["tool.execute.before"](
  { tool: "write", sessionID: "resumed-grandchild", callID: "resumed-child-write-call" },
  { args: { filePath: "src/app.js", content: "const value = true" } },
)

void hooks.event(
  sessionEvent("session.updated", {
    id: "unresolved-grandchild",
    parentID: "unresolved-parent",
  }),
)
await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "write", sessionID: "unresolved-grandchild", callID: "unresolved-child-write-call" },
    { args: { filePath: "src/app.js", content: "const value = true" } },
  ),
  /root session approval could not be resolved.*return this blocker to the parent/,
)

const unresolvedSystem = []
await hooks["experimental.chat.system.transform"](
  { sessionID: "unresolved-session" },
  { system: unresolvedSystem },
)
assert.match(unresolvedSystem.join("\n"), /Do not launch Lavish/)
await assert.rejects(
  hooks["tool.execute.before"](
    { tool: "question", sessionID: "unresolved-session", callID: "unresolved-question-call" },
    { args: {} },
  ),
  /return questions to their parent/,
)

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

const titleLogLines = async () => {
  const content = (await readFile(process.env.HERDR_TITLE_LOG, "utf8")).trim()
  return content ? content.split("\n") : []
}
const commandLogLines = async () => {
  const content = (await readFile(process.env.HERDR_COMMAND_LOG, "utf8")).trim()
  return content ? content.split("\n") : []
}
const subagentMetadataCommands = async () => {
  return (await commandLogLines()).filter((command) =>
    command.startsWith("pane report-metadata"),
  )
}
const workspaceCommands = async () => {
  return (await commandLogLines()).filter((command) => command.startsWith("workspace "))
}

process.env.HERDR_ENV = "1"
process.env.HERDR_TAB_ID = "w1:t-test"
process.env.HERDR_PANE_ID = "w1:p-test"
process.env.HERDR_BIN_PATH = process.env.HERDR_TEST_BIN
await writeFile(process.env.HERDR_TITLE_LOG, "")
await writeFile(process.env.HERDR_COMMAND_LOG, "")
await rm(process.env.HERDR_FAIL_MARKER, { force: true })
process.env.HERDR_FAIL_PANE_METADATA_ONCE = "1"

const titleHooks = await pluginModule.DotfilesHarnessPlugin(
  { directory: process.cwd() },
  { hooksDir: process.env.HARNESS_HOOKS },
)
await titleHooks.event(
  sessionEvent("session.created", {
    id: "root",
    title: "New session - 2026-07-20T12:34:56.789Z",
  }),
)
let subagentCommands = await subagentMetadataCommands()
assert.equal(subagentCommands.length, 2)
assert.equal(subagentCommands[0], subagentCommands[1])
delete process.env.HERDR_FAIL_PANE_METADATA_ONCE
await titleHooks.event(
  sessionEvent("session.created", { id: "child", parentID: "root", title: "Child work" }),
)
await titleHooks.event(
  sessionEvent("session.created", { id: "other-root", title: "Other root" }),
)
assert.deepEqual(await titleLogLines(), [])
subagentCommands = await subagentMetadataCommands()
assert.match(subagentCommands.at(-1), /--token subagent_1=\[run\] Child work/)

await titleHooks.event({
  event: {
    type: "session.status",
    properties: { sessionID: "child", status: { type: "retry" } },
  },
})
subagentCommands = await subagentMetadataCommands()
assert.match(subagentCommands.at(-1), /--token subagent_1=\[retry\] Child work/)

await Promise.all([
  titleHooks.event({
    event: {
      type: "session.status",
      properties: { sessionID: "child", status: { type: "busy" } },
    },
  }),
  titleHooks.event({
    event: {
      type: "session.status",
      properties: { sessionID: "child", status: { type: "retry" } },
    },
  }),
  titleHooks.event({
    event: {
      type: "session.status",
      properties: { sessionID: "child", status: { type: "busy" } },
    },
  }),
])
subagentCommands = await subagentMetadataCommands()
assert.match(subagentCommands.at(-1), /--token subagent_1=\[run\] Child work/)

await titleHooks.event({
  event: { type: "question.asked", properties: { sessionID: "child" } },
})
subagentCommands = await subagentMetadataCommands()
assert.match(subagentCommands.at(-1), /--token subagent_1=\[ask\] Child work/)

for (const index of [2, 3, 4]) {
  await titleHooks.event(
    sessionEvent("session.created", {
      id: `child-${index}`,
      parentID: "root",
      title: `Child ${index} (@explore subagent)`,
    }),
  )
}
subagentCommands = await subagentMetadataCommands()
assert.match(subagentCommands.at(-1), /--token subagent_1=\[ask\] Child work/)
assert.match(subagentCommands.at(-1), /--token subagent_2=\[run\] Child 4/)
assert.match(subagentCommands.at(-1), /--token subagent_3=\[run\] Child 3/)
assert.match(subagentCommands.at(-1), /--token subagent_summary=\+1 active/)
assert.doesNotMatch(subagentCommands.at(-1), /subagent_4/)

await titleHooks.event({
  event: {
    type: "session.status",
    properties: { sessionID: "child", status: { type: "idle" } },
  },
})
subagentCommands = await subagentMetadataCommands()
assert.match(subagentCommands.at(-1), /--token subagent_summary=1 completed/)

await titleHooks.event(
  sessionEvent("session.updated", { id: "root", title: "Generated title" }),
)
await titleHooks.event(
  sessionEvent("session.updated", { id: "root", title: "Generated title" }),
)
await titleHooks.event(
  sessionEvent("session.updated", { id: "other-root", title: "Wrong title" }),
)
assert.deepEqual(await titleLogLines(), ["tab\trename\tw1:t-test\tGenerated title"])
await titleHooks.event(
  sessionEvent("session.updated", { id: "root", title: "Renamed title" }),
)
assert.deepEqual(await titleLogLines(), [
  "tab\trename\tw1:t-test\tGenerated title",
  "tab\trename\tw1:t-test\tRenamed title",
])

await Promise.all([
  titleHooks.event(sessionEvent("session.deleted", { id: "root" })),
  titleHooks.event(
    sessionEvent("session.updated", { id: "other-root", title: "Replacement title" }),
  ),
])
subagentCommands = await subagentMetadataCommands()
assert.match(subagentCommands.at(-1), /--clear-token subagent_1/)
assert.match(subagentCommands.at(-1), /--clear-token subagent_summary/)
await titleHooks.event(
  sessionEvent("session.created", {
    id: "replacement-child",
    parentID: "other-root",
    title: "Replacement child",
  }),
)
subagentCommands = await subagentMetadataCommands()
assert.match(subagentCommands.at(-1), /--token subagent_1=\[run\] Replacement child/)

await writeFile(process.env.HERDR_TITLE_LOG, "")
const resumedTitleHooks = await pluginModule.DotfilesHarnessPlugin(
  { directory: process.cwd() },
  { hooksDir: process.env.HARNESS_HOOKS },
)
await resumedTitleHooks.event(
  sessionEvent("session.updated", { id: "resumed-root", title: "Resumed title" }),
)
await resumedTitleHooks.event(
  sessionEvent("session.updated", { id: "other-resumed-root", title: "Wrong resumed title" }),
)
assert.deepEqual(await titleLogLines(), ["tab\trename\tw1:t-test\tResumed title"])
assert.equal(
  (await commandLogLines()).some((command) => command.startsWith("workspace report-metadata")),
  false,
)

process.env.HERDR_WORKSPACE_ID = "w-task"
process.env.DOTFILES_HERDR_TASK_WORKSPACE = "1"
const checkoutCases = [
  { directory: process.env.OPENCODE_PRIMARY, worktree: "primary" },
  { directory: process.env.OPENCODE_LINKED, worktree: "opencode-linked" },
  { directory: process.env.OPENCODE_POOL, worktree: "7" },
]
for (const [index, checkout] of checkoutCases.entries()) {
  await writeFile(process.env.HERDR_TITLE_LOG, "")
  await writeFile(process.env.HERDR_COMMAND_LOG, "")
  const workspaceHooks = await pluginModule.DotfilesHarnessPlugin(
    { directory: checkout.directory },
    { hooksDir: process.env.HARNESS_HOOKS },
  )
  await workspaceHooks.event(
    sessionEvent("session.updated", { id: `workspace-root-${index}`, title: "Task title" }),
  )
  assert.deepEqual(await titleLogLines(), ["workspace\trename\tw-task\tTask title"])
  assert.deepEqual(await workspaceCommands(), [
    `workspace report-metadata w-task --source dotfiles:checkout --token repo=opencode-repo --token worktree=${checkout.worktree}`,
    "workspace rename w-task Task title",
  ])
}

await writeFile(process.env.HERDR_TITLE_LOG, "")
await writeFile(process.env.HERDR_COMMAND_LOG, "")
await rm(process.env.HERDR_FAIL_MARKER, { force: true })
process.env.HERDR_FAIL_METADATA_ONCE = "1"
const metadataRetryHooks = await pluginModule.DotfilesHarnessPlugin(
  { directory: process.env.OPENCODE_POOL },
  { hooksDir: process.env.HARNESS_HOOKS },
)
const originalWarn = console.warn
const warnings = []
console.warn = (warning) => warnings.push(warning)
await metadataRetryHooks.event(
  sessionEvent("session.created", { id: "metadata-retry", title: "Retry metadata" }),
)
await metadataRetryHooks.event(
  sessionEvent("session.updated", { id: "metadata-retry", title: "Retry metadata" }),
)
console.warn = originalWarn
assert.deepEqual(await workspaceCommands(), [
  "workspace report-metadata w-task --source dotfiles:checkout --token repo=opencode-repo --token worktree=7",
  "workspace rename w-task Retry metadata",
  "workspace report-metadata w-task --source dotfiles:checkout --token repo=opencode-repo --token worktree=7",
])
assert.match(warnings.join("\n"), /herdr workspace report-metadata exited 7/)
delete process.env.HERDR_FAIL_METADATA_ONCE
delete process.env.HERDR_WORKSPACE_ID
delete process.env.DOTFILES_HERDR_TASK_WORKSPACE

await writeFile(process.env.HERDR_TITLE_LOG, "")
await rm(process.env.HERDR_FAIL_MARKER, { force: true })
process.env.HERDR_FAIL_ONCE = "1"
const retryHooks = await pluginModule.DotfilesHarnessPlugin(
  { directory: process.cwd() },
  { hooksDir: process.env.HARNESS_HOOKS },
)
const titleWarnings = []
console.warn = (warning) => titleWarnings.push(warning)
await retryHooks.event(sessionEvent("session.created", { id: "retry", title: "Retry title" }))
await retryHooks.event(sessionEvent("session.updated", { id: "retry", title: "Retry title" }))
console.warn = originalWarn
assert.equal((await titleLogLines()).length, 2)
assert.match(titleWarnings.join("\n"), /herdr tab rename exited 7/)

await writeFile(process.env.HERDR_TITLE_LOG, "")
delete process.env.HERDR_ENV
delete process.env.HERDR_FAIL_ONCE
const outsideHerdrHooks = await pluginModule.DotfilesHarnessPlugin(
  { directory: process.cwd() },
  { hooksDir: process.env.HARNESS_HOOKS },
)
await outsideHerdrHooks.event(
  sessionEvent("session.created", { id: "outside", title: "Outside title" }),
)
assert.deepEqual(await titleLogLines(), [])
JS

printf '%s\n' '{"mcpServers": {}}' >"$CLAUDE"
python3 "$ROOT/scripts/sync_opencode_mcp_from_claude.py" \
	--claude-json "$CLAUDE" \
	--opencode-mcp "$MCP" >/dev/null 2>&1
python3 - "$MCP" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    assert json.load(file) == {"mcp": {}}
PY

grep -q "OpenCode Global Instructions" "$CONFIG_DIR/AGENTS.md" || fail "generated rules are missing"

exit 0
