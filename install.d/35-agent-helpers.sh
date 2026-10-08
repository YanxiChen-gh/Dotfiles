# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

setup_agent_helpers() {
    script_dir=$(resolve_script_dir) || return 1
    auth_helper="$script_dir/scripts/auth-vanta-agents.py"
    auth_skill="$script_dir/shared-skills/auth-vanta-agents"
    mkdir -p "$HOME/.local/bin"
    link_dotfiles_file "$script_dir/scripts/plannotator-safe.sh" "$HOME/.local/bin/plannotator-safe" || return 1
    for helper in open-lavish lavish-axi-safe; do
        target="$HOME/.local/bin/$helper"
        if [ -L "$target" ] && [ "$(readlink "$target")" = "$script_dir/scripts/$helper.sh" ]; then
            rm -f "$target" || return 1
            if [ -e "$target.pre-dotfiles" ] || [ -L "$target.pre-dotfiles" ]; then
                mv "$target.pre-dotfiles" "$target" || return 1
            fi
        fi
    done
    if [ "${WORK_MACHINE:-}" = "1" ]; then
        link_dotfiles_file "$auth_helper" "$HOME/.local/bin/auth-vanta-agents" || return 1
        return 0
    fi

    if [ -L "$HOME/.local/bin/auth-vanta-agents" ] && \
            [ "$(readlink "$HOME/.local/bin/auth-vanta-agents")" = "$auth_helper" ]; then
        rm -f "$HOME/.local/bin/auth-vanta-agents"
        if [ -e "$HOME/.local/bin/auth-vanta-agents.pre-dotfiles" ] || \
                [ -L "$HOME/.local/bin/auth-vanta-agents.pre-dotfiles" ]; then
            mv "$HOME/.local/bin/auth-vanta-agents.pre-dotfiles" "$HOME/.local/bin/auth-vanta-agents"
        fi
    fi
    for target in \
        "$HOME/.claude/skills/auth-vanta-agents" \
        "$HOME/.agents/skills/auth-vanta-agents" \
        "$HOME/.cursor/skills-cursor/auth-vanta-agents"
    do
        if [ -L "$target" ]; then
            case "$(readlink "$target")" in
                "$auth_skill"|"$auth_skill/") rm -f "$target" ;;
            esac
        fi
    done
}
