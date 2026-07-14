# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

# Symlink Codex global instructions, RTK reference, and shared skills.
setup_codex_config() {
    script_dir=$(resolve_script_dir) || return 1
    codex_dir="$HOME/.codex"
    mkdir -p "$codex_dir"

    codex_instructions="$script_dir/codex/AGENTS.md"
    instruction_scope="personal"
    if [ "${WORK_MACHINE:-}" = "1" ]; then
        codex_instructions="$script_dir/codex/AGENTS-work.md"
        instruction_scope="work"
    fi
    if [ -f "$codex_instructions" ]; then
        link_dotfiles_file \
            "$codex_instructions" \
            "$codex_dir/AGENTS.md" \
            "$script_dir/codex/AGENTS.md" \
            "$script_dir/codex/AGENTS-work.md" || return 1
        echo "✅ Codex AGENTS.md linked ($instruction_scope)"
    fi

    rtk_source="$script_dir/codex/RTK.md"
    if [ ! -f "$rtk_source" ]; then
        rtk_source="$script_dir/claude/RTK.md"
    fi
    if [ -f "$rtk_source" ]; then
        link_dotfiles_file "$rtk_source" "$codex_dir/RTK.md" || return 1
        echo "✅ Codex RTK.md linked"
    fi

    # Shared skills (work scope only): use Codex's documented user-level Agent Skills path.
    if [ "$WORK_MACHINE" = "1" ] && [ -d "$script_dir/shared-skills" ]; then
        agent_skills_dir="$HOME/.agents/skills"
        mkdir -p "$agent_skills_dir"
        for skill_dir in "$script_dir/shared-skills"/*/; do
            [ -d "$skill_dir" ] || continue
            name=$(basename "$skill_dir")
            target="$agent_skills_dir/$name"
            if [ -e "$target" ] || [ -L "$target" ]; then
                if [ -L "$target" ] && [ "$(readlink "$target")" = "$skill_dir" ]; then
                    continue
                fi
                echo "⚠️  Preserving unmanaged Codex skill: $target"
                continue
            fi
            ln -s "$skill_dir" "$target"
        done
        echo "✅ Codex shared skills linked (work)"
    fi
}
