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
  "$HOME/.claude/skills/canary-takeover" \
  "$HOME/.agents/skills/scope-gate" \
  "$HOME/.agents/skills/canary-takeover" \
  "$HOME/.claude/skills/record-task-outcome" \
  "$HOME/.agents/skills/record-task-outcome" \
  "$HOME/.claude" \
  "$HOME/.codex"
: >"$HOME/.claude/skills/scope-gate/SKILL.md"
: >"$HOME/.claude/skills/canary-takeover/SKILL.md"
: >"$HOME/.agents/skills/scope-gate/SKILL.md"
: >"$HOME/.agents/skills/canary-takeover/SKILL.md"
: >"$HOME/.claude/skills/record-task-outcome/SKILL.md"
: >"$HOME/.agents/skills/record-task-outcome/SKILL.md"
: >"$HOME/.agent-maturity.env"
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"command":"scope-gate-pretooluse.sh"}]}]}}' >"$HOME/.claude/settings.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"command":"scope-gate-pretooluse.sh"}]}]}}' >"$HOME/.codex/hooks.json"
EOF

cat >"$HOME/.config/opencode/plugins/dotfiles-harness.js" <<'EOF'
const scopeGate = "scope-gate-pretooluse.sh"
const canaryPreflight = "canary_takeover_preflight"
const canaryComplete = "canary_takeover_complete"
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
grep -qFx 'setup_agent_maturity || exit 1' "$ROOT/install.sh"
maturity_line=$(grep -nFx 'setup_agent_maturity || exit 1' "$ROOT/install.sh" | cut -d: -f1)
omp_line=$(grep -nFx 'setup_omp_integration || exit 1' "$ROOT/install.sh" | cut -d: -f1)
[ "$maturity_line" -lt "$omp_line" ] || {
  printf 'FAIL: top-level install does not require maturity before omp\n' >&2
  exit 1
}

cat >"$HOME/.config/opencode/plugins/dotfiles-harness.js" <<'EOF'
const scopeGate = "scope-gate-pretooluse.sh"
const canaryPreflight = "canary_takeover_preflight"
EOF
if setup_agent_maturity >/dev/null 2>&1; then
  printf 'FAIL: setup accepted an OpenCode plugin without canary completion\n' >&2
  exit 1
fi
cat >"$HOME/.config/opencode/plugins/dotfiles-harness.js" <<'EOF'
const scopeGate = "scope-gate-pretooluse.sh"
const canaryPreflight = "canary_takeover_preflight"
const canaryComplete = "canary_takeover_complete"
EOF
OBSIDIAN_ROOT="$TMP/obsidian"
AI_PLUGIN="$OBSIDIAN_ROOT/.claude/plugins/ai-platform-team"
OLD_AI_PLUGIN="$TMP/old-obsidian/.claude/plugins/ai-platform-team"
export OBSIDIAN_ROOT
mkdir -p \
  "$AI_PLUGIN/.claude-plugin" \
  "$AI_PLUGIN/skills/ai-platform-agent" \
  "$AI_PLUGIN/skills/vanta-langsmith" \
  "$OLD_AI_PLUGIN/skills/ai-platform-agent" \
  "$OLD_AI_PLUGIN/skills/retired-ai-skill"
printf '%s\n' '{"name":"ai-platform-team","version":"test"}' >"$AI_PLUGIN/.claude-plugin/plugin.json"
: >"$AI_PLUGIN/skills/ai-platform-agent/SKILL.md"
: >"$AI_PLUGIN/skills/vanta-langsmith/SKILL.md"
: >"$OLD_AI_PLUGIN/skills/ai-platform-agent/SKILL.md"
: >"$OLD_AI_PLUGIN/skills/retired-ai-skill/SKILL.md"
ln -s "$OLD_AI_PLUGIN/skills/ai-platform-agent" "$HOME/.agents/skills/ai-platform-agent"
ln -s "$OLD_AI_PLUGIN/skills/retired-ai-skill" "$HOME/.agents/skills/retired-ai-skill"
ln -s "$OLD_AI_PLUGIN/skills/ai-platform-agent" "$HOME/.agents/skills/custom-ai-alias"

setup_vanta_ai_platform_plugin >/dev/null
[ "$(readlink "$HOME/.agents/skills/ai-platform-agent")" = "$AI_PLUGIN/skills/ai-platform-agent" ]
[ "$(readlink "$HOME/.agents/skills/vanta-langsmith")" = "$AI_PLUGIN/skills/vanta-langsmith" ]
[ ! -e "$HOME/.agents/skills/retired-ai-skill" ] && [ ! -L "$HOME/.agents/skills/retired-ai-skill" ]
[ "$(readlink "$HOME/.agents/skills/custom-ai-alias")" = "$OLD_AI_PLUGIN/skills/ai-platform-agent" ]
jq -e '.enabledPlugins["ai-platform-team@obsidian-local"] == true' "$HOME/.claude/settings.json" >/dev/null

mkdir -p "$AI_PLUGIN/skills/unmanaged-collision" "$HOME/.agents/skills/unmanaged-collision"
: >"$AI_PLUGIN/skills/unmanaged-collision/SKILL.md"
: >"$HOME/.agents/skills/unmanaged-collision/keep"
if link_vanta_ai_platform_agent_skills "$AI_PLUGIN" >/dev/null 2>&1; then
  printf 'FAIL: AI Platform setup replaced an unmanaged Agent Skill\n' >&2
  exit 1
fi
[ -f "$HOME/.agents/skills/unmanaged-collision/keep" ]


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
