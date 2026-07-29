# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

setup_agent_helpers() {
    script_dir=$(resolve_script_dir) || return 1
    mkdir -p "$HOME/.local/bin"
    link_dotfiles_file "$script_dir/scripts/open-lavish.sh" "$HOME/.local/bin/open-lavish" || return 1
    link_dotfiles_file "$script_dir/scripts/lavish-axi-safe.sh" "$HOME/.local/bin/lavish-axi-safe" || return 1
}
