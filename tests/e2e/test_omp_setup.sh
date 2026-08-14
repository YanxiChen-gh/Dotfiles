#!/bin/sh
# E2E: omp installs standalone and selects the standard OpenAI default when available.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-omp-$$"
ORIGINAL_HOME=$HOME
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/home/.local/bin" "$TMP/home/.omp/agent"

cat > "$TMP/bin/curl" <<'EOF'
#!/bin/sh
cat <<'INSTALLER'
#!/bin/sh
[ "$1" = "--binary" ] || exit 91
printf '%s\n' "$*" > "$FAKE_INSTALL_ARGS"
[ "${FAKE_INSTALL_FAIL:-}" != "1" ] || exit 92
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/omp" <<'OMP'
#!/bin/sh
case "${1:-}" in
  --version)
    printf '%s\n' 'omp 17.3.3-test'
    ;;
  config)
    [ -z "${PI_CONFIG_FILES:-}" ] || exit 95
    state_dir=${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}
    mkdir -p "$state_dir"
    case "${2:-}:${3:-}" in
      get:modelRoles)
        if [ -f "$state_dir/fake-model-roles.json" ]; then
          cat "$state_dir/fake-model-roles.json"
        else
          printf '%s\n' '{}'
        fi
        ;;
      set:modelRoles)
        printf '%s\n' "$4" > "$state_dir/fake-model-roles.json"
        ;;
      set:setupVersion)
        printf '%s\n' "$4" > "$state_dir/fake-setup-version"
        ;;
      *) exit 93 ;;
    esac
    ;;
  *) exit 94 ;;
esac
OMP
chmod +x "$HOME/.local/bin/omp"
INSTALLER
EOF
chmod +x "$TMP/bin/curl"

# A functional npm/Bun shim at the managed path must still be replaced by the
# standalone binary.
mkdir -p "$TMP/home/.local/lib/node_modules/@oh-my-pi/pi-coding-agent/dist"
cat > "$TMP/home/.local/lib/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js" <<'EOF'
#!/bin/sh
printf '%s\n' 'omp/npm-test'
EOF
chmod +x "$TMP/home/.local/lib/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js"
ln -s "../lib/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js" "$TMP/home/.local/bin/omp"

(
  export HOME="$TMP/home"
  export PATH="$TMP/bin:/usr/bin:/bin"
  export OMP_EXPERIMENT=1
  export FAKE_INSTALL_ARGS="$TMP/install-args"
  . "$ROOT/install.d/10-helpers.sh"
  . "$ROOT/install.d/66-omp.sh"
  install_omp
)

[ "$(cat "$TMP/install-args")" = "--binary" ] || {
  echo "FAIL: official installer did not receive --binary" >&2
  exit 1
}
PATH="/usr/bin:/bin" "$TMP/home/.local/bin/omp" --version | grep -F 'omp 17.3.3-test' >/dev/null
[ ! -L "$TMP/home/.local/bin/omp" ] || {
  echo "FAIL: npm/Bun omp symlink was retained" >&2
  exit 1
}

# A failed standalone download restores the previously working npm launcher.
rm -f "$TMP/home/.local/bin/omp"
ln -s "../lib/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js" "$TMP/home/.local/bin/omp"
if (
  export HOME="$TMP/home"
  export PATH="$TMP/bin:/usr/bin:/bin"
  export OMP_EXPERIMENT=1
  export FAKE_INSTALL_ARGS="$TMP/failed-install-args"
  export FAKE_INSTALL_FAIL=1
  . "$ROOT/install.d/10-helpers.sh"
  . "$ROOT/install.d/66-omp.sh"
  install_omp
); then
  echo "FAIL: failed standalone install returned success" >&2
  exit 1
fi
[ -L "$TMP/home/.local/bin/omp" ] || {
  echo "FAIL: npm/Bun launcher was not restored after install failure" >&2
  exit 1
}
[ "$("$TMP/home/.local/bin/omp" --version)" = "omp/npm-test" ] || {
  echo "FAIL: restored npm/Bun launcher does not work" >&2
  exit 1
}

# Numeric OMP_VERSION values keep their old interface and map to GitHub's v-tag.
rm -f "$TMP/home/.local/bin/omp"
(
  export HOME="$TMP/home"
  export PATH="$TMP/bin:/usr/bin:/bin"
  export OMP_EXPERIMENT=1
  export OMP_VERSION=17.3.3
  export FAKE_INSTALL_ARGS="$TMP/pinned-install-args"
  . "$ROOT/install.d/10-helpers.sh"
  . "$ROOT/install.d/66-omp.sh"
  install_omp
)
[ "$(cat "$TMP/pinned-install-args")" = "--binary --ref v17.3.3" ] || {
  echo "FAIL: numeric OMP_VERSION was not normalized to a release tag" >&2
  exit 1
}

# Migration removes only links created by the old Dotfiles setup.
OLD_AGENT="$TMP/old-agent"
UNMANAGED_AGENT="$TMP/unmanaged-agent"
mkdir -p "$OLD_AGENT/extensions" "$UNMANAGED_AGENT/extensions"
ln -s "$ROOT/omp/agent/config.yml" "$OLD_AGENT/config.yml"
ln -s "$ROOT/omp/agent/models.yml" "$OLD_AGENT/models.yml"
printf 'restored: true\n' > "$OLD_AGENT/config.yml.pre-dotfiles"
printf '%s\n' '{"smol":"openai/gpt-5.4-mini"}' > "$OLD_AGENT/fake-model-roles.json"
printf 'keep: true\n' > "$UNMANAGED_AGENT/config.yml"
printf 'keep: true\n' > "$UNMANAGED_AGENT/models.yml"

(
  export HOME="$TMP/home"
  export OMP_EXPERIMENT=1
  export OPENAI_API_KEY=test-openai-key
  export PI_CONFIG_FILES="$TMP/project-overlay.yml"
  export PI_CODING_AGENT_DIR="$OLD_AGENT"
  . "$ROOT/install.d/10-helpers.sh"
  . "$ROOT/install.d/66-omp.sh"
  resolve_script_dir() { printf '%s\n' "$ROOT"; }
  setup_omp_config
)
[ ! -L "$OLD_AGENT/config.yml" ] && grep -F 'restored: true' "$OLD_AGENT/config.yml" >/dev/null || {
  echo "FAIL: pre-Dotfiles omp config was not restored" >&2
  exit 1
}
[ ! -e "$OLD_AGENT/models.yml" ] && [ ! -L "$OLD_AGENT/models.yml" ] || {
  echo "FAIL: legacy managed models link remains" >&2
  exit 1
}
[ -L "$OLD_AGENT/extensions/dotfiles-harness.ts" ] || {
  echo "FAIL: harness extension was not linked" >&2
  exit 1
}
jq -e '.default == "openai/gpt-5.6-sol" and .smol == "openai/gpt-5.4-mini"' \
  "$OLD_AGENT/fake-model-roles.json" >/dev/null || {
  echo "FAIL: OpenAI default did not preserve existing model roles" >&2
  exit 1
}
[ "$(cat "$OLD_AGENT/fake-setup-version")" = "1" ] || {
  echo "FAIL: OpenAI environment did not complete native setup" >&2
  exit 1
}

(
  export HOME="$TMP/home"
  export OMP_EXPERIMENT=1
  unset OPENAI_API_KEY
  export PI_CODING_AGENT_DIR="$UNMANAGED_AGENT"
  . "$ROOT/install.d/10-helpers.sh"
  . "$ROOT/install.d/66-omp.sh"
  resolve_script_dir() { printf '%s\n' "$ROOT"; }
  setup_omp_config
)
grep -F 'keep: true' "$UNMANAGED_AGENT/config.yml" >/dev/null
grep -F 'keep: true' "$UNMANAGED_AGENT/models.yml" >/dev/null
[ ! -e "$UNMANAGED_AGENT/fake-model-roles.json" ] || {
  echo "FAIL: model defaults changed without OPENAI_API_KEY" >&2
  exit 1
}

# Exercise the extension hook when Bun is available; otherwise retain static
# assertions so CI still catches the recursive turn-start implementation.
BUN_BIN=$(command -v bun 2>/dev/null || true)
if [ -z "$BUN_BIN" ] && [ -x "$ORIGINAL_HOME/.bun/bin/bun" ]; then
  BUN_BIN="$ORIGINAL_HOME/.bun/bin/bun"
fi
if [ -n "$BUN_BIN" ]; then
  mkdir -p "$TMP/maturity/scripts"
  cat > "$TMP/maturity/scripts/scope-gate-userpromptsubmit.sh" <<'EOF'
#!/bin/sh
printf '%s\n' 'scope brief'
EOF
  chmod +x "$TMP/maturity/scripts/scope-gate-userpromptsubmit.sh"
  cat > "$TMP/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_LOG"
EOF
  chmod +x "$TMP/bin/herdr"
  cat > "$TMP/test-extension.ts" <<'EOF'
import { pathToFileURL } from "node:url"

const extensionPath = process.argv[2]
const handlers = new Map<string, (event: unknown, context: unknown) => Promise<unknown>>()
const pi = {
  cwd: process.cwd(),
  setLabel() {},
  on(name: string, handler: (event: unknown, context: unknown) => Promise<unknown>) {
    handlers.set(name, handler)
  },
}
const extension = (await import(pathToFileURL(extensionPath).href)).default
await extension(pi)
if (handlers.has("turn_start")) throw new Error("scope injection still registers turn_start")
const handler = handlers.get("before_agent_start")
if (!handler) throw new Error("before_agent_start scope hook is missing")
const result = await handler(
  { type: "before_agent_start", prompt: "hi", systemPrompt: ["base"] },
  { sessionManager: { getSessionId: () => "test-session" } },
) as { systemPrompt?: string[] }
if (JSON.stringify(result.systemPrompt) !== JSON.stringify(["base", "scope brief"])) {
  throw new Error(`unexpected system prompt: ${JSON.stringify(result)}`)
}

const toolCall = handlers.get("tool_call")
if (!toolCall) throw new Error("tool_call hook is missing")
const blocked = await toolCall(
  { toolName: "bash", input: { command: "open-lavish /tmp/review.html" } },
  { mode: "print", sessionManager: { getSessionId: () => "task-session" } },
) as { block?: boolean }
if (blocked.block !== true) throw new Error("non-UI task session may launch Lavish")
const foregroundPoll = await toolCall(
  { toolName: "bash", input: { command: "lavish-axi-safe poll /tmp/review.html" } },
  { mode: "tui", sessionManager: { getSessionId: () => "root-session" } },
) as { block?: boolean }
if (foregroundPoll.block !== true) throw new Error("foreground Lavish poll was allowed")
const delegatedPoll = await toolCall(
  { toolName: "hub", input: { op: "start", application: "lavish-axi-safe", args: ["poll", "/tmp/review.html"] } },
  { mode: "tui", sessionManager: { getSessionId: () => "root-session" } },
) as { block?: boolean }
if (delegatedPoll.block !== true) throw new Error("non-Bash Lavish poll was allowed")
const allowed = await toolCall(
  { toolName: "bash", input: { command: "lavish-axi-safe poll /tmp/review.html", async: true } },
  { mode: "tui", sessionManager: { getSessionId: () => "root-session" } },
) as { block?: boolean } | undefined
if (allowed?.block === true) throw new Error("interactive root session cannot launch Lavish")

const sessionStart = handlers.get("session_start")
const turnEnd = handlers.get("turn_end")
if (!sessionStart || !turnEnd) throw new Error("Herdr title hooks are missing")
let title: string | undefined
const intervals: Array<() => Promise<void> | void> = []
const titleContext = {
  mode: "tui",
  sessionManager: {
    getSessionId: () => "root-session",
    getSessionName: () => title,
  },
  setInterval(callback: () => Promise<void> | void) {
    intervals.push(callback)
    return 1
  },
}
await sessionStart({ type: "session_start" }, titleContext)
if (intervals.length !== 1) throw new Error("missing title sync interval")
title = "Generated omp title"
await intervals[0]?.()
await Bun.sleep(50)
await turnEnd({ type: "turn_end" }, titleContext)
await Bun.sleep(50)
title = "Renamed omp title"
await intervals[0]?.()
await Bun.sleep(50)
EOF
  : > "$TMP/herdr.log"
  HOME="$TMP/home" AGENT_MATURITY_HOME="$TMP/maturity" \
    HERDR_ENV=1 HERDR_WORKSPACE_ID=test-workspace HERDR_TAB_ID=test-tab \
    DOTFILES_HERDR_TASK_WORKSPACE=1 HERDR_BIN_PATH="$TMP/bin/herdr" HERDR_LOG="$TMP/herdr.log" \
    "$BUN_BIN" "$TMP/test-extension.ts" "$ROOT/omp/agent/extensions/dotfiles-harness.ts"
  expected_titles="workspace rename test-workspace Generated omp title
workspace rename test-workspace Renamed omp title"
  [ "$(cat "$TMP/herdr.log")" = "$expected_titles" ] || {
    echo "FAIL: omp title changes were not applied once to the task workspace" >&2
    exit 1
  }
else
  grep -F 'pi.on("before_agent_start"' "$ROOT/omp/agent/extensions/dotfiles-harness.ts" >/dev/null
  ! grep -F 'pi.on("turn_start"' "$ROOT/omp/agent/extensions/dotfiles-harness.ts" >/dev/null
  grep -F 'pi.on("session_start"' "$ROOT/omp/agent/extensions/dotfiles-harness.ts" >/dev/null
  grep -F 'pi.on("turn_end"' "$ROOT/omp/agent/extensions/dotfiles-harness.ts" >/dev/null
fi

: > "$TMP/herdr-integration.log"
cat > "$TMP/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_INTEGRATION_LOG"
EOF
chmod +x "$TMP/bin/herdr"
(
  export HOME="$TMP/home"
  export PATH="$TMP/bin:/usr/bin:/bin"
  export OMP_EXPERIMENT=1
  export HERDR_INTEGRATION_LOG="$TMP/herdr-integration.log"
  . "$ROOT/install.d/66-omp.sh"
  install_herdr_omp_integration
)
[ "$(cat "$TMP/herdr-integration.log")" = "integration install omp" ] || {
  echo "FAIL: native Herdr omp integration was not installed" >&2
  exit 1
}

echo "omp setup tests passed."
