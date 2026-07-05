# shellcheck shell=sh
# Sourced by ../install.sh — function definitions only.

# Install superpowers plugin for Claude Code (user scope — always available)
setup_superpowers_plugin() {
    echo "Setting up superpowers plugin for Claude Code..."

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping superpowers plugin setup."
        return 1
    fi

    if claude plugin list 2>/dev/null | grep -q "superpowers"; then
        echo "✅ superpowers plugin already installed"
        return 0
    fi

    # Register the superpowers marketplace if not already known
    if ! claude plugin marketplace list 2>/dev/null | grep -q "superpowers-marketplace"; then
        echo "Adding superpowers-marketplace..."
        if ! claude plugin marketplace add obra/superpowers-marketplace 2>/dev/null; then
            echo "⚠️  Warning: Failed to add superpowers-marketplace"
            return 1
        fi
    fi

    echo "Installing superpowers plugin..."
    if claude plugin install superpowers@superpowers-marketplace 2>/dev/null; then
        echo "✅ superpowers plugin installed"
    else
        echo "⚠️  Warning: Failed to install superpowers plugin"
        return 1
    fi
}

# Setup Claude Code config: user-level CLAUDE.md and skills
setup_claude_config() {
    script_dir=$(resolve_script_dir) || return 1
    claude_dir="$HOME/.claude"
    mkdir -p "$claude_dir"

    # Symlink user-level CLAUDE.md + RTK.md (work scope only)
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$script_dir/claude/CLAUDE.md" ]; then
        rm -f "$claude_dir/CLAUDE.md"
        ln -s "$script_dir/claude/CLAUDE.md" "$claude_dir/CLAUDE.md"
        echo "✅ Claude Code CLAUDE.md linked (work)"
    fi
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$script_dir/claude/RTK.md" ]; then
        rm -f "$claude_dir/RTK.md"
        ln -s "$script_dir/claude/RTK.md" "$claude_dir/RTK.md"
        echo "✅ Claude Code RTK.md linked (work)"
    fi

    # Symlink skills (work scope only): claude/skills + shared-skills (both tools via install)
    if [ "$WORK_MACHINE" = "1" ]; then
        mkdir -p "$claude_dir/skills"
        for source_skills in "$script_dir/claude/skills" "$script_dir/shared-skills"; do
            if [ ! -d "$source_skills" ]; then
                continue
            fi
            for skill_dir in "$source_skills"/*/; do
                [ -d "$skill_dir" ] || continue
                name=$(basename "$skill_dir")
                rm -rf "$claude_dir/skills/$name"
                ln -s "$skill_dir" "$claude_dir/skills/$name"
            done
        done
        echo "✅ Claude Code skills linked (work)"
    fi

    # Register the comment-bar PostToolUse hook (work scope): nudges the model to apply the
    # comment bar after JS/TS edits, since current models over-comment by default. Idempotent
    # (deduped on the script name). Kill switch + retirement trigger live in the script itself.
    hook_script="$script_dir/claude/hooks/comment-self-check.sh"
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$hook_script" ]; then
        chmod +x "$hook_script" 2>/dev/null || true
        COMMENT_HOOK_CMD="bash $hook_script" python3 - "$claude_dir/settings.json" <<'PY'
import json, os, sys

path, cmd = sys.argv[1], os.environ["COMMENT_HOOK_CMD"]
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

post = cfg.setdefault("hooks", {}).setdefault("PostToolUse", [])
present = any(
    "comment-self-check.sh" in h.get("command", "")
    for entry in post
    for h in entry.get("hooks", [])
)
if not present:
    post.append({"matcher": "Write|Edit", "hooks": [{"type": "command", "command": cmd}]})
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("registered comment-bar PostToolUse hook")
else:
    print("comment-bar hook already registered")
PY
        echo "✅ Claude Code comment-bar hook registered (work)"
    fi

    # Register the verify-gate PreToolUse(Bash) hook (work scope): blocks `gh pr create`
    # when the PR body lacks verification evidence + an independent-review/grading section
    # (Trust L2→L3 lever). Idempotent (deduped on the script name). Fail-open + kill switch
    # (VERIFY_GATE=off) + retirement trigger live in the script itself.
    vg_hook="$script_dir/claude/hooks/verify-gate-pretooluse.sh"
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$vg_hook" ]; then
        chmod +x "$vg_hook" "$script_dir/claude/hooks/verify-gate-check.py" 2>/dev/null || true
        VERIFY_HOOK_CMD="bash $vg_hook" python3 - "$claude_dir/settings.json" <<'PY'
import json, os, sys

path, cmd = sys.argv[1], os.environ["VERIFY_HOOK_CMD"]
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

pre = cfg.setdefault("hooks", {}).setdefault("PreToolUse", [])
present = any(
    "verify-gate-pretooluse.sh" in h.get("command", "")
    for entry in pre
    for h in entry.get("hooks", [])
)
if not present:
    pre.append({"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]})
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("registered verify-gate PreToolUse hook")
else:
    print("verify-gate hook already registered")
PY
        echo "✅ Claude Code verify-gate hook registered (work)"
    fi

    # Register the pr-authoring gate PreToolUse(Bash) hook (work scope): blocks `gh pr create`
    # / `gh pr edit --body` when an LLM judge (claude -p) grades the body as bloated against
    # pr-authoring.md, so the guide lands on the first draft instead of a post-hoc /simplify-pr
    # cleanup (Spec lever). Idempotent (deduped on the script name). Fail-open + kill switch
    # (PR_AUTHORING_GATE=off) + retirement trigger live in the script itself.
    pag_hook="$script_dir/claude/hooks/pr-authoring-gate-pretooluse.sh"
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$pag_hook" ]; then
        chmod +x "$pag_hook" "$script_dir/claude/hooks/pr-authoring-gate-check.py" 2>/dev/null || true
        PAG_HOOK_CMD="bash $pag_hook" python3 - "$claude_dir/settings.json" <<'PY'
import json, os, sys

path, cmd = sys.argv[1], os.environ["PAG_HOOK_CMD"]
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

pre = cfg.setdefault("hooks", {}).setdefault("PreToolUse", [])
present = any(
    "pr-authoring-gate-pretooluse.sh" in h.get("command", "")
    for entry in pre
    for h in entry.get("hooks", [])
)
if not present:
    pre.append({"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]})
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("registered pr-authoring gate PreToolUse hook")
else:
    print("pr-authoring gate hook already registered")
PY
        echo "✅ Claude Code pr-authoring gate hook registered (work)"
    fi
}

# Advisor system (github.com/YanxiChen-gh/advisors): clone the context/skill repos and
# link the /advisor + /advisor-setup skills. The work root holds work-specific advisor
# contexts (real project names), so it is cloned on work machines only.
setup_advisors() {
    advisors_clone_or_pull() {
        # GIT_TERMINAL_PROMPT=0: on an unauthenticated machine, fail into the warning
        # path instead of stalling the install on a credential prompt.
        if [ -d "$2/.git" ]; then
            GIT_TERMINAL_PROMPT=0 git -C "$2" pull --ff-only --quiet 2>/dev/null || true
        else
            GIT_TERMINAL_PROMPT=0 git clone --quiet "$1" "$2" 2>/dev/null
        fi
    }

    if ! advisors_clone_or_pull https://github.com/YanxiChen-gh/advisors.git "$HOME/advisors"; then
        echo "⚠️  advisors repo not accessible — skipping advisor setup"
        return 0
    fi
    if [ "$WORK_MACHINE" = "1" ]; then
        advisors_clone_or_pull https://github.com/VantaInc/yanxi-vanta-advisor.git "$HOME/advisors-vanta" \
            || echo "⚠️  work advisor root not accessible — vanta advisor unavailable"
    fi

    mkdir -p "$HOME/.claude/skills"
    for skill_dir in "$HOME/advisors/skills"/*/; do
        [ -d "$skill_dir" ] || continue
        name=$(basename "$skill_dir")
        rm -rf "$HOME/.claude/skills/$name"
        ln -s "$skill_dir" "$HOME/.claude/skills/$name"
    done
    echo "✅ advisor skills linked"
}

# Install the agent-maturity engine. It lives in its own PUBLIC repo
# (github.com/YanxiChen-gh/agent-maturity); the engine's bootstrap.sh does all the heavy
# lifting (clone-or-pull → install.sh → skills + scope-gate hooks + `li` + env). So this is
# just the one-liner — same line any teammate puts in their own dotfiles. Data stays private.
setup_agent_maturity() {
    echo "Setting up agent-maturity engine..."
    local boot="${AGENT_MATURITY_BOOTSTRAP_URL:-https://raw.githubusercontent.com/YanxiChen-gh/agent-maturity/main/bootstrap.sh}"
    local data_repo="${AGENT_MATURITY_DATA_REPO:-YanxiChen-gh/agent-maturity-data}"
    if curl -fsSL "$boot" | bash -s -- --data-repo "$data_repo" \
         --name "$(git config --global user.name)" --email "$(git config --global user.email)" >/dev/null; then
        echo "✅ agent-maturity installed (via engine bootstrap)"
    else
        echo "⚠️  agent-maturity install failed (curl $boot | bash)"
    fi
}

# Enable Vanta AI Platform Claude Code plugin and sync its skills to Cursor.
setup_vanta_ai_platform_plugin() {
    if [ "$WORK_MACHINE" != "1" ]; then
        return 0
    fi

    obsidian_root="${OBSIDIAN_ROOT:-/workspaces/obsidian}"
    if [ ! -d "$obsidian_root/.claude/plugins/ai-platform-team" ]; then
        echo "ℹ️  obsidian checkout not found; skipping AI Platform plugin setup"
        return 0
    fi

    echo "Setting up Vanta AI Platform plugin for Claude Code and Cursor..."

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$HOME/.claude/settings.json" <<'PY'
import json
import os
import sys

path = os.path.expanduser(sys.argv[1])
os.makedirs(os.path.dirname(path), exist_ok=True)

data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

data.setdefault("enabledPlugins", {})["ai-platform-team@obsidian-local"] = True

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
        echo "✅ AI Platform plugin enabled for Claude Code"
    else
        echo "⚠️  Python3 not found; skipping Claude Code plugin enablement"
    fi

    script_dir=$(resolve_script_dir) || return 1
    sync_script="$script_dir/sync-claude-skills-to-repo.sh"
    if [ -x "$sync_script" ]; then
        "$sync_script" "$obsidian_root" || true
    else
        echo "⚠️  Cursor skill sync script not found or not executable: $sync_script"
    fi
}

