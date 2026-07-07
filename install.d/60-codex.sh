# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

# Symlink Codex global instructions and RTK reference.
setup_codex_config() {
    script_dir=$(dirname "$(readlink -f "$0")")
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
}

