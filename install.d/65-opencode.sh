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

install_herdr_opencode_integration() {
    herdr_install_dir=${HERDR_INSTALL_DIR:-$HOME/.local/bin}
    herdr_bin=$(command -v herdr 2>/dev/null || true)
    if [ -z "$herdr_bin" ] && [ -x "$herdr_install_dir/herdr" ]; then
        herdr_bin="$herdr_install_dir/herdr"
    fi
    if [ -z "$herdr_bin" ]; then
        echo "⚠️  Herdr is unavailable; skipping its OpenCode integration"
        return 0
    fi

    if ! "$herdr_bin" integration install opencode; then
        echo "⚠️  Warning: Herdr OpenCode integration installation failed"
        return 1
    fi

    herdr_plugin="$HOME/.config/opencode/plugins/herdr-agent-state.js"
    opencode_plugin="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/herdr-agent-state.js"
    if [ "$opencode_plugin" != "$herdr_plugin" ]; then
        mkdir -p "$(dirname "$opencode_plugin")"
        link_dotfiles_file "$herdr_plugin" "$opencode_plugin" "$herdr_plugin" || return 1
    fi

    echo "✅ Herdr OpenCode integration installed"
}

ensure_opencode_path() {
    path_line='export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"'
    old_path_line='export PATH="$HOME/.opencode/bin:$PATH"'
    for profile in "$HOME/.profile" "$HOME/.bash_profile"; do
        if [ "$profile" = "$HOME/.bash_profile" ] && [ ! -e "$profile" ]; then
            continue
        fi
        if [ -f "$profile" ] && grep -qFx "$old_path_line" "$profile"; then
            replacement=$(mktemp "${TMPDIR:-/tmp}/opencode-path.XXXXXX") || return 1
            while IFS= read -r line || [ -n "$line" ]; do
                if [ "$line" = "$old_path_line" ]; then
                    printf '%s\n' "$path_line"
                else
                    printf '%s\n' "$line"
                fi
            done < "$profile" > "$replacement"
            mv "$replacement" "$profile"
        elif [ ! -f "$profile" ] || ! grep -qF '.opencode/bin' "$profile"; then
            printf '\n# OpenCode\n%s\n' "$path_line" >>"$profile"
        fi
    done
}

setup_opencode_config() {
    script_dir=$(resolve_script_dir) || return 1
    source_dir="$script_dir/opencode"
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    plugin_dir="$config_dir/plugins"

    mkdir -p "$plugin_dir" "$HOME/.local/bin"
    link_dotfiles_file "$source_dir/opencode" "$HOME/.local/bin/opencode" || return 1
    if [ -e "$config_dir/opencode.json" ] || [ -L "$config_dir/opencode.json" ]; then
        link_dotfiles_file "$source_dir/opencode.jsonc" "$config_dir/opencode.json" || return 1
        rm -f "$config_dir/opencode.json"
    fi
    link_dotfiles_file "$source_dir/opencode.jsonc" "$config_dir/opencode.jsonc" || return 1

    if [ -e "$config_dir/tui.json" ] || [ -L "$config_dir/tui.json" ]; then
        link_dotfiles_file "$source_dir/tui.jsonc" "$config_dir/tui.json" || return 1
        rm -f "$config_dir/tui.json"
    fi
    link_dotfiles_file "$source_dir/tui.jsonc" "$config_dir/tui.jsonc" || return 1

    opencode_instructions="$source_dir/AGENTS.md"
    instruction_scope="personal"
    if [ "${WORK_MACHINE:-}" = "1" ]; then
        opencode_instructions="$source_dir/AGENTS-work.md"
        instruction_scope="work"
    fi
    link_dotfiles_file \
        "$opencode_instructions" \
        "$config_dir/AGENTS.md" \
        "$source_dir/AGENTS.md" \
        "$source_dir/AGENTS-work.md" || return 1

    link_dotfiles_file "$source_dir/plugins/dotfiles-harness.js" "$plugin_dir/dotfiles-harness.js" || return 1

    doc_discovery_source="$source_dir/skills/vanta-doc-discovery/SKILL.md"
    doc_discovery_dir="$config_dir/skills/vanta-doc-discovery"
    doc_discovery_target="$doc_discovery_dir/SKILL.md"
    if [ "${WORK_MACHINE:-}" = "1" ]; then
        mkdir -p "$doc_discovery_dir"
        link_dotfiles_file "$doc_discovery_source" "$doc_discovery_target" "$doc_discovery_source" || return 1
    else
        if [ -L "$doc_discovery_target" ] && [ "$(readlink "$doc_discovery_target")" = "$doc_discovery_source" ]; then
            rm -f "$doc_discovery_target"
        fi
        if [ ! -e "$doc_discovery_target" ] && [ ! -L "$doc_discovery_target" ] && { [ -e "$doc_discovery_target.pre-dotfiles" ] || [ -L "$doc_discovery_target.pre-dotfiles" ]; }; then
            mv "$doc_discovery_target.pre-dotfiles" "$doc_discovery_target"
        fi
        rmdir "$doc_discovery_dir" 2>/dev/null || true
    fi

    echo "✅ OpenCode config, TUI settings, $instruction_scope rules, and harness linked"
}
