# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

# Setup Claude Code config: user-level CLAUDE.md and skills
setup_claude_config() {
    script_dir=$(resolve_script_dir) || return 1
    claude_dir="$HOME/.claude"
    mkdir -p "$claude_dir"

    claude_instructions="$script_dir/claude/CLAUDE.md"
    instruction_scope="personal"
    if [ "${WORK_MACHINE:-}" = "1" ]; then
        claude_instructions="$script_dir/claude/CLAUDE-work.md"
        instruction_scope="work"
    fi
    if [ -f "$claude_instructions" ]; then
        link_dotfiles_file \
            "$claude_instructions" \
            "$claude_dir/CLAUDE.md" \
            "$script_dir/claude/CLAUDE.md" \
            "$script_dir/claude/CLAUDE-work.md" || return 1
        echo "✅ Claude Code CLAUDE.md linked ($instruction_scope)"
    fi
    if [ -f "$script_dir/claude/RTK.md" ]; then
        link_dotfiles_file "$script_dir/claude/RTK.md" "$claude_dir/RTK.md" || return 1
        echo "✅ Claude Code RTK.md linked"
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

    # Earlier installations registered hooks for scripts that are no longer installed.
    if [ -f "$claude_dir/settings.json" ]; then
        python3 - "$claude_dir/settings.json" "$script_dir" <<'PY'
import json
from pathlib import Path
import shlex
import sys

path = Path(sys.argv[1])
with path.open() as f:
    config = json.load(f)
hooks = config.get("hooks", {})
changed = False
for event, script in (
    ("PreToolUse", "verify-gate-pretooluse.sh"),
    ("PreToolUse", "pr-authoring-gate-pretooluse.sh"),
    ("PostToolUse", "comment-self-check.sh"),
):
    target = Path(sys.argv[2], "claude/hooks", script).resolve()
    groups = []
    for group in hooks.get(event, []):
        remaining = []
        for hook in group.get("hooks", []):
            try:
                words = shlex.split(hook.get("command", ""))
            except ValueError:
                words = []
            if words and words[-1].endswith("/" + script) and Path(words[-1]).expanduser().resolve() == target:
                changed = True
            else:
                remaining.append(hook)
        if remaining or "hooks" not in group:
            groups.append({**group, "hooks": remaining} if "hooks" in group else group)
    if event in hooks:
        hooks[event] = groups
if changed:
    path.write_text(json.dumps(config, indent=2) + "\n")
PY
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
        echo "⚠️  advisors repo not accessible - skipping advisor setup"
        return 0
    fi
    if [ "$WORK_MACHINE" = "1" ]; then
        advisors_clone_or_pull https://github.com/VantaInc/yanxi-vanta-advisor.git "$HOME/advisors-vanta" \
            || echo "⚠️  work advisor root not accessible - vanta advisor unavailable"
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

# Enable Vanta AI Platform skills for Claude Code, shared Agent Skills clients, and Cursor.
link_vanta_ai_platform_agent_skills() {
    plugin_root=$1
    agent_skills_dir="$HOME/.agents/skills"
    skills_root="$plugin_root/skills"
    mkdir -p "$agent_skills_dir"

    for target in "$agent_skills_dir"/*; do
        [ -L "$target" ] || continue
        current_source=$(readlink "$target")
        name=$(basename "$target")
        case "$current_source" in
            */.claude/plugins/ai-platform-team/skills/"$name"|*/.claude/plugins/ai-platform-team/skills/"$name"/)
                [ -f "$skills_root/$name/SKILL.md" ] || rm -f "$target"
                ;;
        esac
    done

    for skill_dir in "$skills_root"/*/; do
        [ -f "$skill_dir/SKILL.md" ] || continue
        source_dir=${skill_dir%/}
        name=$(basename "$source_dir")
        target="$agent_skills_dir/$name"

        if [ -L "$target" ]; then
            current_source=$(readlink "$target")
            if [ "$current_source" = "$source_dir" ]; then
                continue
            fi
            case "$current_source" in
                */.claude/plugins/ai-platform-team/skills/"$name"|*/.claude/plugins/ai-platform-team/skills/"$name"/)
                    rm -f "$target"
                    ;;
            esac
        fi

        if [ -e "$target" ] || [ -L "$target" ]; then
            echo "⚠️  Preserving unmanaged Agent Skill: $target"
            return 1
        fi
        ln -s "$source_dir" "$target" || return 1
    done
}

setup_vanta_ai_platform_plugin() {
    if [ "$WORK_MACHINE" != "1" ]; then
        return 0
    fi

    obsidian_root="${OBSIDIAN_ROOT:-/workspaces/obsidian}"
    if [ ! -d "$obsidian_root/.claude/plugins/ai-platform-team" ]; then
        echo "ℹ️  obsidian checkout not found; skipping AI Platform plugin setup"
        return 0
    fi

    echo "Setting up Vanta AI Platform plugin for Claude Code, shared Agent Skills clients, and Cursor..."

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
    if link_vanta_ai_platform_agent_skills "$obsidian_root/.claude/plugins/ai-platform-team"; then
        echo "✅ AI Platform skills linked for Codex, OpenCode, and omp"
    else
        echo "⚠️  AI Platform shared skill setup is incomplete"
        return 1
    fi


    script_dir=$(resolve_script_dir) || return 1
    sync_script="$script_dir/sync-claude-skills-to-repo.sh"
    if [ -x "$sync_script" ]; then
        "$sync_script" "$obsidian_root" || true
    else
        echo "⚠️  Cursor skill sync script not found or not executable: $sync_script"
    fi
}

# Enable Obsidian Doc Discovery for Claude Code. OpenCode uses its adapter from
# opencode/skills because the repository skill names Claude-specific Glean tools.
setup_vanta_doc_discovery_plugin() {
    if [ "${WORK_MACHINE:-}" != "1" ]; then
        return 0
    fi

    obsidian_root="${OBSIDIAN_ROOT:-/workspaces/obsidian}"
    if [ ! -d "$obsidian_root/.claude/plugins/vanta-doc-discovery" ]; then
        echo "ℹ️  obsidian checkout not found; skipping Doc Discovery plugin setup"
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "⚠️  Python3 not found; skipping Doc Discovery plugin enablement"
        return 0
    fi

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

data.setdefault("enabledPlugins", {})["vanta-doc-discovery@obsidian-local"] = True

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    echo "✅ Doc Discovery plugin enabled for Claude Code"
}
