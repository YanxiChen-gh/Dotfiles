# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

# Setup Cursor IDE configuration
# Symlinks settings, keybindings, snippets, and skills from Dotfiles
setup_cursor() {
    echo "Setting up Cursor IDE configuration..."

    # Skip if Cursor is not installed (e.g., in Gitpod/Codespaces)
    if ! command -v cursor >/dev/null 2>&1 && [ ! -d "/Applications/Cursor.app" ] && [ ! -d "$HOME/.cursor" ]; then
        echo "ℹ️  Cursor not installed, skipping Cursor setup."
        return 0
    fi

    script_dir=$(resolve_script_dir) || return 1
    cursor_dotfiles="$script_dir/cursor"

    if [ ! -d "$cursor_dotfiles" ]; then
        echo "⚠️  Warning: cursor/ directory not found in Dotfiles. Skipping Cursor setup."
        return 1
    fi

    # Determine Cursor config paths based on OS
    if [ "$OS" = "macos" ]; then
        cursor_user_dir="$HOME/Library/Application Support/Cursor/User"
        cursor_home_dir="$HOME/.cursor"
    else
        cursor_user_dir="$HOME/.config/Cursor/User"
        cursor_home_dir="$HOME/.cursor"
    fi

    # Create directories if they don't exist
    mkdir -p "$cursor_user_dir"
    mkdir -p "$cursor_home_dir"

    # Handle settings.json - merge with work settings if WORK_MACHINE=1
    if [ -f "$cursor_dotfiles/settings.json" ]; then
        echo "Setting up Cursor settings.json..."
        rm -f "$cursor_user_dir/settings.json"
        
        if [ "$WORK_MACHINE" = "1" ] && [ -f "$cursor_dotfiles/settings-work.json" ]; then
            # Merge personal + work settings using Python
            if command -v python3 >/dev/null 2>&1; then
                python3 -c "
import json
with open('$cursor_dotfiles/settings.json') as f:
    personal = json.load(f)
with open('$cursor_dotfiles/settings-work.json') as f:
    work = json.load(f)
# Remove comment field from work settings
work.pop('_comment', None)
# Merge: work settings override personal
merged = {**personal, **work}
with open('$cursor_user_dir/settings.json', 'w') as f:
    json.dump(merged, f, indent=4)
"
                echo "✅ settings.json created (personal + work merged)"
            else
                # Fallback: just use personal settings
                ln -s "$cursor_dotfiles/settings.json" "$cursor_user_dir/settings.json"
                echo "⚠️  Python not found, using personal settings only"
            fi
        else
            # Personal machine: symlink personal settings
            ln -s "$cursor_dotfiles/settings.json" "$cursor_user_dir/settings.json"
            echo "✅ settings.json linked"
        fi
    fi

    # Symlink keybindings.json
    if [ -f "$cursor_dotfiles/keybindings.json" ]; then
        echo "Linking Cursor keybindings.json..."
        rm -f "$cursor_user_dir/keybindings.json"
        ln -s "$cursor_dotfiles/keybindings.json" "$cursor_user_dir/keybindings.json"
        echo "✅ keybindings.json linked"
    fi

    # Symlink snippets directory
    if [ -d "$cursor_dotfiles/snippets" ]; then
        echo "Linking Cursor snippets..."
        rm -rf "$cursor_user_dir/snippets"
        ln -s "$cursor_dotfiles/snippets" "$cursor_user_dir/snippets"
        echo "✅ snippets linked"
    fi

    # Agent skills: personal cursor/skills + work shared-skills (same skill dirs for Claude + Cursor)
    if [ -d "$cursor_dotfiles/skills" ] || { [ "$WORK_MACHINE" = "1" ] && [ -d "$script_dir/shared-skills" ]; }; then
        echo "Linking Cursor agent skills..."
        rm -rf "$cursor_home_dir/skills-cursor"
        mkdir -p "$cursor_home_dir/skills-cursor"
        if [ -d "$cursor_dotfiles/skills" ]; then
            for skill_dir in "$cursor_dotfiles/skills"/*/; do
                [ -d "$skill_dir" ] || continue
                name=$(basename "$skill_dir")
                rm -f "$cursor_home_dir/skills-cursor/$name"
                ln -s "$skill_dir" "$cursor_home_dir/skills-cursor/$name"
            done
        fi
        if [ "$WORK_MACHINE" = "1" ] && [ -d "$script_dir/shared-skills" ]; then
            for skill_dir in "$script_dir/shared-skills"/*/; do
                [ -d "$skill_dir" ] || continue
                name=$(basename "$skill_dir")
                rm -f "$cursor_home_dir/skills-cursor/$name"
                ln -s "$skill_dir" "$cursor_home_dir/skills-cursor/$name"
            done
        fi
        echo "✅ agent skills linked"
    fi

    # Agent hooks (RTK shell rewrite for Cursor Agent)
    if [ -f "$cursor_dotfiles/hooks.json" ]; then
        echo "Linking Cursor hooks.json..."
        rm -f "$cursor_home_dir/hooks.json"
        ln -s "$cursor_dotfiles/hooks.json" "$cursor_home_dir/hooks.json"
        echo "✅ hooks.json linked (RTK preToolUse)"
    fi

    # Symlink rules directory (merge personal + work rules)
    if [ -d "$cursor_dotfiles/rules" ] || [ -d "$cursor_dotfiles/rules-work" ]; then
        echo "Linking Cursor rules..."
        mkdir -p "$cursor_home_dir/rules"
        
        # Link personal rules
        if [ -d "$cursor_dotfiles/rules" ]; then
            for rule in "$cursor_dotfiles/rules"/*.mdc; do
                [ -f "$rule" ] || continue
                name=$(basename "$rule")
                rm -f "$cursor_home_dir/rules/$name"
                ln -s "$rule" "$cursor_home_dir/rules/$name"
            done
            echo "✅ personal rules linked"
        fi
        
        # Link work rules only if WORK_MACHINE=1
        if [ "$WORK_MACHINE" = "1" ] && [ -d "$cursor_dotfiles/rules-work" ]; then
            for rule in "$cursor_dotfiles/rules-work"/*.mdc; do
                [ -f "$rule" ] || continue
                name=$(basename "$rule")
                rm -f "$cursor_home_dir/rules/$name"
                ln -s "$rule" "$cursor_home_dir/rules/$name"
            done
            echo "✅ work rules linked"
        fi
    fi

    echo "✅ Cursor configuration setup complete"
}

# Install extensions from a file
# Usage: install_extensions_from_file <file_path>
install_extensions_from_file() {
    extensions_file="$1"
    
    [ -f "$extensions_file" ] || return 1

    installed=0
    failed=0
    while IFS= read -r extension || [ -n "$extension" ]; do
        # Skip empty lines and comments
        [ -z "$extension" ] && continue
        case "$extension" in \#*) continue ;; esac

        echo "  Installing $extension..."
        if cursor --install-extension "$extension" 2>/dev/null; then
            installed=$((installed + 1))
        else
            echo "    ⚠️  Failed to install $extension"
            failed=$((failed + 1))
        fi
    done < "$extensions_file"

    echo "  Installed: $installed, failed: $failed"
}

# Install Cursor extensions from extensions.txt (and extensions-work.txt if WORK_MACHINE=1)
install_cursor_extensions() {
    echo "Installing Cursor extensions..."
    script_dir=$(resolve_script_dir) || return 1

    # Check if cursor CLI is available
    if ! command -v cursor >/dev/null 2>&1; then
        echo "⚠️  Warning: 'cursor' command not found. Skipping extension installation."
        echo "   Extensions can be installed manually or after adding cursor to PATH."
        echo "   On macOS: Add /Applications/Cursor.app/Contents/Resources/app/bin to PATH"
        return 1
    fi

    # Install personal extensions
    if [ -f "$script_dir/cursor/extensions.txt" ]; then
        echo "Installing personal extensions..."
        install_extensions_from_file "$script_dir/cursor/extensions.txt"
    fi

    # Install work extensions if WORK_MACHINE=1
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$script_dir/cursor/extensions-work.txt" ]; then
        echo "Installing work extensions..."
        install_extensions_from_file "$script_dir/cursor/extensions-work.txt"
    fi

    echo "✅ Extension installation complete"
}

