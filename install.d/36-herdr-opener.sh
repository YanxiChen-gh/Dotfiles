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

    if ! command -v swiftc >/dev/null 2>&1; then
        echo "⚠️  Apple's Command Line Tools are required to build the native Split View helper."
        echo "   Install them with xcode-select --install, then rerun setup."
        return 1
    fi
    helper_dir="$HOME/.local/libexec/dotfiles"
    mkdir -p "$helper_dir"
    helper_tmp=$(mktemp "$helper_dir/herdr-split-view.XXXXXX") || return 1
    if ! swiftc "$script_dir/herdr/split-view.swift" -o "$helper_tmp"; then
        rm -f "$helper_tmp"
        return 1
    fi
    mv -f "$helper_tmp" "$helper_dir/herdr-split-view"
    echo "✅ Installed native Herdr Split View opener (WezTerm + Google Chrome)"
    echo "   Allow WezTerm Accessibility and Google Chrome Automation when macOS asks."
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
