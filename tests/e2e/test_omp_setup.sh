#!/bin/sh
# E2E: omp installs as a standalone binary and leaves runtime auth/model state to omp.
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
printf '%s\n' 'omp 17.3.3-test'
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
printf 'keep: true\n' > "$UNMANAGED_AGENT/config.yml"
printf 'keep: true\n' > "$UNMANAGED_AGENT/models.yml"

(
  export HOME="$TMP/home"
  export OMP_EXPERIMENT=1
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

(
  export HOME="$TMP/home"
  export OMP_EXPERIMENT=1
  export PI_CODING_AGENT_DIR="$UNMANAGED_AGENT"
  . "$ROOT/install.d/10-helpers.sh"
  . "$ROOT/install.d/66-omp.sh"
  resolve_script_dir() { printf '%s\n' "$ROOT"; }
  setup_omp_config
)
grep -F 'keep: true' "$UNMANAGED_AGENT/config.yml" >/dev/null
grep -F 'keep: true' "$UNMANAGED_AGENT/models.yml" >/dev/null

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
EOF
  HOME="$TMP/home" AGENT_MATURITY_HOME="$TMP/maturity" \
    "$BUN_BIN" "$TMP/test-extension.ts" "$ROOT/omp/agent/extensions/dotfiles-harness.ts"
else
  grep -F 'pi.on("before_agent_start"' "$ROOT/omp/agent/extensions/dotfiles-harness.ts" >/dev/null
  ! grep -F 'pi.on("turn_start"' "$ROOT/omp/agent/extensions/dotfiles-harness.ts" >/dev/null
fi

echo "omp setup tests passed."
