# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

# Symlink Codex global instructions, RTK reference, and shared skills.
setup_codex_config() {
    script_dir=$(resolve_script_dir) || return 1
    codex_dir="$HOME/.codex"
    mkdir -p "$codex_dir"

    if [ -f "$script_dir/codex/AGENTS.md" ]; then
        rm -f "$codex_dir/AGENTS.md"
        ln -s "$script_dir/codex/AGENTS.md" "$codex_dir/AGENTS.md"
        echo "✅ Codex AGENTS.md linked"
    fi

    rtk_source="$script_dir/codex/RTK.md"
    if [ ! -f "$rtk_source" ]; then
        rtk_source="$script_dir/claude/RTK.md"
    fi
    if [ -f "$rtk_source" ]; then
        rm -f "$codex_dir/RTK.md"
        ln -s "$rtk_source" "$codex_dir/RTK.md"
        echo "✅ Codex RTK.md linked"
    fi

    # Shared skills (work scope only): mirror the Claude/Cursor symlink so Codex can
    # follow the same SKILL.md files. Codex has no native skill auto-load, so codex/AGENTS.md
    # points at ~/.codex/skills/ and the agent reads the relevant SKILL.md on demand.
    if [ "$WORK_MACHINE" = "1" ] && [ -d "$script_dir/shared-skills" ]; then
        mkdir -p "$codex_dir/skills"
        for skill_dir in "$script_dir/shared-skills"/*/; do
            [ -d "$skill_dir" ] || continue
            name=$(basename "$skill_dir")
            rm -rf "$codex_dir/skills/$name"
            ln -s "$skill_dir" "$codex_dir/skills/$name"
        done
        echo "✅ Codex shared skills linked (work)"
    fi
}

