#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-e2e-plannotator.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin" "$TMP/home/.local/bin" "$TMP/downloads" "$TMP/installer/install.d"
ln -s "$(command -v node)" "$TMP/bin/node"
HOME="$TMP/home"
PATH="$TMP/bin:$HOME/.local/bin:/usr/bin:/bin"
TMPDIR="$TMP/downloads"
XDG_STATE_HOME="$TMP/state"
unset CLAUDE_CONFIG_DIR CODEX_HOME XDG_CONFIG_HOME
FAKE_LOG="$TMP/invocations"
export HOME PATH TMPDIR XDG_STATE_HOME FAKE_LOG
: >"$FAKE_LOG"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = -fsSL ] && [ "$2" = https://plannotator.ai/install.sh ] && [ "$3" = -o ]
printf 'download\n' >>"$FAKE_LOG"
[ "${FAKE_DOWNLOAD_FAIL:-0}" = 0 ] || exit 22
cat >"$4" <<'INSTALL'
#!/bin/bash
set -eu
[ "$#" = 1 ] && [ "$1" = --minimal ]
printf 'binary-install\n' >>"$FAKE_LOG"
[ "${FAKE_INSTALL_FAIL:-0}" = 0 ] || exit 17
[ "${FAKE_MISSING_BINARY:-0}" = 0 ] || exit 0
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/bin/plannotator"
chmod +x "$HOME/.local/bin/plannotator"
INSTALL
EOF

cat >"$TMP/bin/npx" <<'EOF'
#!/bin/sh
set -eu
printf 'npx %s\n' "$*" >>"$FAKE_LOG"
case "$2" in
    add)
        skill=
        json=0
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --skill) skill=$2; shift 2 ;;
                --json) json=1; shift ;;
                *) shift ;;
            esac
        done
        [ "$skill" = plannotator ] || exit 0
        [ "${FAKE_SKILL_FAIL:-0}" = 0 ] || exit 19
        if [ "${FAKE_AGENT_FAIL:-0}" = 1 ]; then
            [ "$json" = 0 ] && exit 0
            exit 1
        fi
        rm -rf "$HOME/.agents/skills/plannotator"
        mkdir -p "$HOME/.agents/skills/plannotator"
        if [ "${FAKE_MISSING_SKILL:-0}" = 0 ]; then
            printf 'fixture skill\n' >"$HOME/.agents/skills/plannotator/SKILL.md"
        fi
        claude_skill="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/plannotator"
        mkdir -p "$(dirname "$claude_skill")"
        rm -rf "$claude_skill"
        if [ "${FAKE_MISSING_CLAUDE:-0}" = 0 ]; then
            ln -s "$HOME/.agents/skills/plannotator" "$claude_skill"
        fi
        node <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const lockPath = process.env.XDG_STATE_HOME
    ? path.join(process.env.XDG_STATE_HOME, 'skills/.skill-lock.json')
    : path.join(process.env.HOME, '.agents/.skill-lock.json');
const lock = fs.existsSync(lockPath) ? JSON.parse(fs.readFileSync(lockPath, 'utf8')) : {skills:{}};
lock.skills.plannotator = {source:'backnotprop/plannotator'};
fs.mkdirSync(path.dirname(lockPath), {recursive:true});
fs.writeFileSync(lockPath, JSON.stringify(lock));
NODE
        printf 'skill-installed plannotator\n' >>"$FAKE_LOG"
        ;;
    remove)
        [ "$3" = lavish ] || exit 0
        [ "${FAKE_REMOVE_FAIL:-0}" = 0 ] || exit 23
        rm -rf "$HOME/.agents/skills/lavish"
        rm -rf "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/lavish"
        printf 'skill-removed lavish\n' >>"$FAKE_LOG"
        ;;
esac
EOF
chmod +x "$TMP/bin/curl" "$TMP/bin/npx"

. "$ROOT/install.d/10-helpers.sh"
. "$ROOT/install.d/35-agent-helpers.sh"
. "$ROOT/install.d/80-tools.sh"
resolve_script_dir() { printf '%s\n' "$ROOT"; }

for failure in FAKE_DOWNLOAD_FAIL FAKE_INSTALL_FAIL FAKE_MISSING_BINARY; do
    if env "$failure=1" sh -c '. "$1/install.d/80-tools.sh"; install_plannotator' sh "$ROOT" >/dev/null 2>&1; then
        fail "binary installation ignored $failure"
    fi
    [ ! -e "$HOME/.local/bin/plannotator" ] || fail "failed installation exposed a binary"
done
printf 'unmanaged binary collision\n' >"$HOME/.local/bin/plannotator"
if install_plannotator >/dev/null 2>&1; then fail "binary collision was overwritten"; fi
[ "$(cat "$HOME/.local/bin/plannotator")" = 'unmanaged binary collision' ] || fail "binary collision lost"
rm -f "$HOME/.local/bin/plannotator"
install_plannotator
[ -x "$HOME/.local/bin/plannotator" ] || fail "official binary was not installed"
: >"$FAKE_LOG"
install_plannotator
[ ! -s "$FAKE_LOG" ] || fail "existing binary was reinstalled"
for download in "$TMPDIR"/*; do
    [ ! -e "$download" ] || fail "installer download was not cleaned up"
done

# Exercise real orchestration, replacing unrelated setup in a disposable checkout.
cp "$ROOT/install.sh" "$TMP/installer/install.sh"
cat >"$TMP/installer/install.d/00-fixture.sh" <<EOF
. "$ROOT/install.d/80-tools.sh"
EOF
for function in install_from_apt install_python_if_missing install_node_if_missing install_typescript_language_service \
    create_symlinks setup_agent_helpers install_neovim setup_nvim_config setup_cloudev_tasks \
    setup_herdr_config setup_treehouse_config setup_wezterm_config setup_herdr_opener_client \
    setup_ona_default_shell setup_work_machine install_from_url install_opencode install_agent_browser \
    setup_herdr_opener_plugin install_langsmith_cli install_gastown setup_cursor install_cursor_extensions \
    setup_langsmith_mcp setup_figma_mcp_cli remove_chrome_devtools_axi setup_claude_config \
    setup_opencode_config install_herdr_opencode_integration setup_codex_config setup_advisors \
    setup_rtk setup_agent_maturity setup_omp_integration setup_superpowers_plugin \
    setup_vanta_ai_platform_plugin setup_vanta_doc_discovery_plugin setup_work_tools \
    sync_cursor_mcp_from_claude sync_opencode_mcp_from_claude setup_omp_rtk setup_omp_mcp; do
    printf '%s() { :; }\n' "$function" >>"$TMP/installer/install.d/00-fixture.sh"
done

mkdir -p "$XDG_STATE_HOME/skills" "$HOME/.agents/skills/lavish" "$HOME/.claude/skills"
printf '%s\n' '{"version":3,"skills":{"lavish":{"source":"kunchenguid/lavish-axi"}}}' >"$XDG_STATE_HOME/skills/.skill-lock.json"
ln -s ../../.agents/skills/lavish "$HOME/.claude/skills/lavish"
run_installer() {
    WORK_MACHINE=0 WORKSPACES_DIR="$TMP/workspaces" sh "$TMP/installer/install.sh" >"$TMP/install.out" 2>&1
}
for target in "$HOME/.agents/skills/plannotator" "$TMP/custom-claude/skills/plannotator" \
        "$HOME/.cursor/skills/plannotator" "$TMP/custom-codex/skills/plannotator" \
        "$TMP/custom-config/opencode/skills/plannotator"; do
    mkdir -p "$target"
    printf 'user skill content\n' >"$target/user-file"
    : >"$FAKE_LOG"
    if CLAUDE_CONFIG_DIR="$TMP/custom-claude" CODEX_HOME="$TMP/custom-codex" \
            XDG_CONFIG_HOME="$TMP/custom-config" install_plannotator_skill >"$TMP/collision.out" 2>&1; then
        fail "unmanaged skill collision accepted: $target"
    fi
    [ "$(cat "$target/user-file")" = 'user skill content' ] || fail "unmanaged skill collision lost"
    [ ! -s "$FAKE_LOG" ] || fail "skill CLI ran before collision refusal"
    rm -rf "$target"
done
rm -f "$HOME/.local/bin/plannotator"
if FAKE_INSTALL_FAIL=1 run_installer; then fail "binary failure was ignored by orchestration"; fi
[ -d "$HOME/.agents/skills/lavish" ] || fail "binary failure removed Lavish"
if FAKE_SKILL_FAIL=1 run_installer; then fail "replacement skill failure was ignored"; fi
[ -d "$HOME/.agents/skills/lavish" ] || fail "replacement failure removed Lavish"
for failure in FAKE_MISSING_SKILL FAKE_MISSING_CLAUDE; do
    if env "$failure=1" WORK_MACHINE=0 WORKSPACES_DIR="$TMP/workspaces" \
            sh "$TMP/installer/install.sh" >"$TMP/install.out" 2>&1; then
        fail "missing replacement descriptor ignored: $failure"
    fi
    [ -d "$HOME/.agents/skills/lavish" ] || fail "missing replacement removed Lavish"
done
if FAKE_REMOVE_FAIL=1 run_installer; then fail "Lavish removal failure was ignored"; fi
[ -d "$HOME/.agents/skills/lavish" ] || fail "failed removal destroyed Lavish"
if FAKE_AGENT_FAIL=1 run_installer; then fail "per-agent failures reported success"; fi
[ -d "$HOME/.agents/skills/lavish" ] || fail "per-agent failure removed Lavish"
: >"$FAKE_LOG"
run_installer
[ -d "$HOME/.agents/skills/plannotator" ] || fail "replacement skill missing"
[ ! -e "$HOME/.agents/skills/lavish" ] || fail "managed Lavish skill was not removed"
node - "$FAKE_LOG" <<'NODE'
const fs = require('node:fs');
const calls = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n');
const add = calls.indexOf('skill-installed plannotator');
const remove = calls.indexOf('skill-removed lavish');
if (add < 0 || remove <= add) throw new Error('Lavish removal did not follow replacement installation');
NODE
CLAUDE_CONFIG_DIR="$TMP/custom-claude" install_plannotator_skill >/dev/null
[ -f "$TMP/custom-claude/skills/plannotator/SKILL.md" ] || fail "replacement missing from configured Claude home"

mkdir -p "$HOME/.agents/skills/lavish"
printf 'custom\n' >"$HOME/.agents/skills/lavish/user-file"
printf '%s\n' '{"skills":{"lavish":{"source":"user/custom"}}}' >"$XDG_STATE_HOME/skills/.skill-lock.json"
remove_lavish_skill
[ "$(cat "$HOME/.agents/skills/lavish/user-file")" = custom ] || fail "unmanaged skill was removed"
printf '%s\n' '{"skills":{"lavish":{"source":"kunchenguid/lavish-axi"}}}' >"$XDG_STATE_HOME/skills/.skill-lock.json"
printf 'custom agent skill\n' >"$HOME/.claude/skills/lavish"
remove_lavish_skill >/dev/null
[ -f "$HOME/.claude/skills/lavish" ] || fail "unmanaged agent skill was removed"
rm -f "$HOME/.claude/skills/lavish"
mkdir -p "$TMP/custom-claude/skills/lavish"
printf 'custom config skill\n' >"$TMP/custom-claude/skills/lavish/user-file"
CLAUDE_CONFIG_DIR="$TMP/custom-claude" remove_lavish_skill >/dev/null
[ "$(cat "$TMP/custom-claude/skills/lavish/user-file")" = 'custom config skill' ] || fail "overridden Claude skill was removed"
printf 'invalid json\n' >"$XDG_STATE_HOME/skills/.skill-lock.json"
if remove_lavish_skill >/dev/null 2>&1; then fail "invalid ownership metadata was ignored"; fi

# Managed helper links retire, while collisions and their backups survive.
ln -s "$ROOT/scripts/open-lavish.sh" "$HOME/.local/bin/open-lavish"
ln -s "$ROOT/scripts/lavish-axi-safe.sh" "$HOME/.local/bin/lavish-axi-safe"
printf 'original helper\n' >"$HOME/.local/bin/open-lavish.pre-dotfiles"
printf 'custom safe helper\n' >"$HOME/.local/bin/plannotator-safe"
WORK_MACHINE=0 setup_agent_helpers >/dev/null
[ "$(readlink "$HOME/.local/bin/plannotator-safe")" = "$ROOT/scripts/plannotator-safe.sh" ] || fail "safe helper missing"
[ "$(cat "$HOME/.local/bin/plannotator-safe.pre-dotfiles")" = 'custom safe helper' ] || fail "helper collision was not backed up"
[ "$(cat "$HOME/.local/bin/open-lavish")" = 'original helper' ] || fail "retired helper backup not restored"
[ ! -L "$HOME/.local/bin/lavish-axi-safe" ] || fail "obsolete managed helper remains"
ln -s "$TMP/foreign-helper" "$HOME/.local/bin/lavish-axi-safe"
printf 'leave backup\n' >"$HOME/.local/bin/lavish-axi-safe.pre-dotfiles"
WORK_MACHINE=0 setup_agent_helpers >/dev/null
[ "$(readlink "$HOME/.local/bin/lavish-axi-safe")" = "$TMP/foreign-helper" ] || fail "unmanaged obsolete helper link changed"
[ "$(cat "$HOME/.local/bin/lavish-axi-safe.pre-dotfiles")" = 'leave backup' ] || fail "unmanaged helper backup changed"
rm -f "$HOME/.local/bin/plannotator-safe"
printf 'collision\n' >"$HOME/.local/bin/plannotator-safe"
if WORK_MACHINE=0 setup_agent_helpers >/dev/null; then fail "occupied backup was overwritten"; fi
[ "$(cat "$HOME/.local/bin/plannotator-safe")" = collision ] || fail "collision lost after setup failure"

cat >"$TMP/bin/plannotator" <<'EOF'
#!/usr/bin/env node
const fs = require('node:fs');
fs.writeFileSync(process.env.FAKE_CAPTURE, JSON.stringify({args:process.argv.slice(2),env:process.env,input:fs.readFileSync(0,'utf8')}));
process.stdout.write('review feedback\n');
process.stderr.write('native diagnostics\n');
process.exit(Number(process.env.FAKE_STATUS || 0));
EOF
chmod +x "$TMP/bin/plannotator"
FAKE_CAPTURE="$TMP/capture.json"
export FAKE_CAPTURE
printf 'artifact input\n' | PLANNOTATOR_REMOTE=1 PLANNOTATOR_SKIP_BROWSER_OPEN=0 \
    PLANNOTATOR_GLIMPSE=1 PLANNOTATOR_SHARE=enabled PLANNOTATOR_AI=enabled PLANNOTATOR_PORT=49271 \
    "$ROOT/scripts/plannotator-safe.sh" annotate 'a document.md' --gate --json --browser Firefox >"$TMP/feedback" 2>"$TMP/diagnostics"
node - "$FAKE_CAPTURE" <<'NODE'
const fs = require('node:fs');
const {args, env, input} = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (JSON.stringify(args) !== JSON.stringify(['annotate','a document.md','--gate','--json','--browser','Firefox'])) throw new Error('argument boundaries changed');
if (input !== 'artifact input\n') throw new Error('stdin changed');
if (env.PLANNOTATOR_REMOTE !== '0' || env.PLANNOTATOR_SKIP_BROWSER_OPEN !== '1' || env.PLANNOTATOR_GLIMPSE !== '0' || env.PLANNOTATOR_SHARE !== 'disabled') throw new Error('unsafe environment reached CLI');
if (env.PLANNOTATOR_PORT !== '49271' || env.PLANNOTATOR_AI !== 'enabled') throw new Error('native optional settings changed');
NODE
[ "$(cat "$TMP/feedback")" = 'review feedback' ] || fail "stdout feedback changed"
[ "$(cat "$TMP/diagnostics")" = 'native diagnostics' ] || fail "stderr changed"
status=0
FAKE_STATUS=37 "$ROOT/scripts/plannotator-safe.sh" review --base main </dev/null >/dev/null 2>&1 || status=$?
[ "$status" = 37 ] || fail "CLI failure status changed"
rm -f "$FAKE_CAPTURE"
for bypass in --tailscale --open; do
    if "$ROOT/scripts/plannotator-safe.sh" annotate artifact.md "$bypass" </dev/null >/dev/null 2>&1; then
        fail "safety bypass $bypass accepted"
    fi
    [ ! -e "$FAKE_CAPTURE" ] || fail "unsafe CLI invocation launched"
done
printf 'OK: Plannotator installer, migration, and safe CLI fixtures\n'
