#!/bin/sh
# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

install_opencode() {
    echo "Checking for OpenCode..."
    if command -v opencode >/dev/null 2>&1; then
        ensure_opencode_path
        echo "✅ OpenCode already installed ($(opencode --version))"
        return 0
    fi

    echo "Installing OpenCode..."
    if curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path; then
        export PATH="$HOME/.opencode/bin:$PATH"
        ensure_opencode_path
        echo "✅ OpenCode installed successfully"
    else
        echo "⚠️  Warning: OpenCode installation failed"
        echo "   Try manually: curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path"
        return 1
    fi
}

ensure_opencode_path() {
    path_line='export PATH="$HOME/.opencode/bin:$PATH"'
    for profile in "$HOME/.profile" "$HOME/.bash_profile"; do
        if [ "$profile" = "$HOME/.bash_profile" ] && [ ! -e "$profile" ]; then
            continue
        fi
        if [ ! -f "$profile" ] || ! grep -qF '.opencode/bin' "$profile"; then
            printf '\n# OpenCode\n%s\n' "$path_line" >>"$profile"
        fi
    done
}

link_opencode_file() {
    source_file=$1
    target_file=$2

    if [ -L "$target_file" ] && [ "$(readlink "$target_file")" = "$source_file" ]; then
        return 0
    fi

    if [ -e "$target_file" ] || [ -L "$target_file" ]; then
        backup_file="$target_file.pre-dotfiles"
        if [ -e "$backup_file" ] || [ -L "$backup_file" ]; then
            echo "⚠️  OpenCode setup kept unmanaged file because backup already exists: $target_file"
            return 1
        fi
        mv "$target_file" "$backup_file"
        echo "ℹ️  Preserved existing OpenCode file at $backup_file"
    fi

    ln -s "$source_file" "$target_file"
}

setup_opencode_config() {
    script_dir=$(resolve_script_dir) || return 1
    source_dir="$script_dir/opencode"
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    plugin_dir="$config_dir/plugins"

    mkdir -p "$plugin_dir"
    if [ -e "$config_dir/opencode.json" ] || [ -L "$config_dir/opencode.json" ]; then
        link_opencode_file "$source_dir/opencode.jsonc" "$config_dir/opencode.json" || return 1
        rm -f "$config_dir/opencode.json"
    fi
    link_opencode_file "$source_dir/opencode.jsonc" "$config_dir/opencode.jsonc" || return 1

    if [ -e "$config_dir/tui.json" ] || [ -L "$config_dir/tui.json" ]; then
        link_opencode_file "$source_dir/tui.jsonc" "$config_dir/tui.json" || return 1
        rm -f "$config_dir/tui.json"
    fi
    link_opencode_file "$source_dir/tui.jsonc" "$config_dir/tui.jsonc" || return 1

    link_opencode_file "$source_dir/AGENTS.md" "$config_dir/AGENTS.md" || return 1

    link_opencode_file "$source_dir/plugins/dotfiles-harness.js" "$plugin_dir/dotfiles-harness.js" || return 1

    echo "✅ OpenCode config, TUI settings, global rules, and harness linked"
}
