#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-agent-maturity-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

HOME="$TMP/home"
XDG_CONFIG_HOME="$HOME/.config"
FAKE_BOOT="$TMP/bootstrap.sh"
AGENT_MATURITY_BOOTSTRAP_URL="https://example.invalid/bootstrap.sh"
AGENT_MATURITY_DATA_REPO="example/agent-maturity-data"
WORK_MACHINE=1
export HOME XDG_CONFIG_HOME FAKE_BOOT AGENT_MATURITY_BOOTSTRAP_URL AGENT_MATURITY_DATA_REPO WORK_MACHINE
mkdir -p "$HOME/.config/opencode/plugins" "$HOME/.codex"

cat >"$FAKE_BOOT" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >"$HOME/bootstrap-args"
mkdir -p \
  "$HOME/.claude/skills/scope-gate" \
  "$HOME/.agents/skills/scope-gate" \
  "$HOME/.claude" \
  "$HOME/.codex"
: >"$HOME/.claude/skills/scope-gate/SKILL.md"
: >"$HOME/.agents/skills/scope-gate/SKILL.md"
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"command":"scope-gate-pretooluse.sh"}]}]}}' >"$HOME/.claude/settings.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"command":"scope-gate-pretooluse.sh"}]}]}}' >"$HOME/.codex/hooks.json"
EOF

cat >"$HOME/.config/opencode/plugins/dotfiles-harness.js" <<'EOF'
const scopeGate = "scope-gate-pretooluse.sh"
EOF

resolve_script_dir() {
  printf '%s\n' "$ROOT"
}

curl() {
  cat "$FAKE_BOOT"
}

# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/50-claude.sh
. "$ROOT/install.d/50-claude.sh"
# shellcheck source=../../install.d/60-codex.sh
. "$ROOT/install.d/60-codex.sh"

output=$(setup_agent_maturity)
printf '%s\n' "$output" | grep -q 'installed for Claude Code, Codex, and OpenCode'
printf '%s\n' "$output" | grep -q 'open /hooks once'
grep -q -- '--data-repo example/agent-maturity-data' "$HOME/bootstrap-args"

mkdir -p "$HOME/.agents/skills/connect-mongo"
: >"$HOME/.agents/skills/connect-mongo/keep"
setup_codex_config >/dev/null
[ -L "$HOME/.agents/skills/full-verification-workflow" ]
[ "$(readlink "$HOME/.agents/skills/full-verification-workflow")" = "$ROOT/shared-skills/full-verification-workflow/" ]
[ -f "$HOME/.agents/skills/connect-mongo/keep" ]

rm "$HOME/.agents/skills/full-verification-workflow"
ln -s "$TMP/unmanaged-skill" "$HOME/.agents/skills/full-verification-workflow"
setup_codex_config >/dev/null
[ "$(readlink "$HOME/.agents/skills/full-verification-workflow")" = "$TMP/unmanaged-skill" ]
