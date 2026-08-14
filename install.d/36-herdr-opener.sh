# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

setup_herdr_opener_client() {
    if [ "$OS" != "macos" ]; then
        return 0
    fi

    script_dir=$(resolve_script_dir) || return 1
    mkdir -p "$HOME/.local/bin"
    link_dotfiles_file \
        "$script_dir/herdr/herdr-remote.sh" \
        "$HOME/.local/bin/herdr-remote" || return 1

    if ! command -v brew >/dev/null 2>&1; then
        echo "⚠️  Homebrew is required for remote Herdr browser opening."
        echo "   Install opener manually: brew install superbrothers/opener/opener"
        return 1
    fi
    if ! command -v opener >/dev/null 2>&1; then
        brew install superbrothers/opener/opener || return 1
    fi
    if brew services start opener; then
        echo "✅ Local opener service is running"
    else
        echo "⚠️  Could not start opener; retry with: brew services start opener"
        return 1
    fi
}

setup_herdr_opener_plugin() {
    if [ "$OS" != "linux" ]; then
        return 0
    fi
    if [ "${IS_ON_ONA:-}" != "true" ] && [ "${HERDR_REMOTE_OPENER_SERVER:-}" != "1" ]; then
        return 0
    fi
    if ! command -v ss >/dev/null 2>&1; then
        echo "⚠️  ss is required to verify the Herdr opener relay stays on loopback"
        return 1
    fi
    if ! command -v herdr >/dev/null 2>&1; then
        echo "⚠️  Herdr is required before linking the remote opener plugin"
        return 1
    fi

    script_dir=$(resolve_script_dir) || return 1
    if herdr plugin link "$script_dir/herdr/remote-opener" >/dev/null; then
        echo "✅ Linked Herdr remote opener plugin"
    else
        echo "⚠️  Could not link the Herdr remote opener plugin"
        return 1
    fi
}
