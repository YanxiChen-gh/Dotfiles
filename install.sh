#!/bin/sh

# Detect OS
case "$(uname -s)" in
    Darwin*) OS="macos" ;;
    Linux*)  OS="linux" ;;
    *)       OS="unknown" ;;
esac

# Install a package using apt-get
# Usage: install_from_apt <package_name>
install_from_apt() {
    package_name=$1
    echo "Installing $package_name..."
    if sudo apt-get update && sudo apt-get install -y "$package_name"; then
        echo "✅ $package_name installed successfully"
    else
        echo "⚠️  Warning: $package_name installation failed, but continuing with setup"
        echo "   You can manually install later by running: sudo apt-get update && sudo apt-get install -y $package_name"
    fi
}

# Setup LangSmith MCP server configuration
# Usage: setup_langsmith_mcp
setup_langsmith_mcp() {
    echo "Setting up LangSmith MCP server..."

    # Check if Claude Code is available
    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping LangSmith MCP setup."
        echo "   Install Claude Code first, then run: claude mcp add ..."
        return 1
    fi

    # Check if LangSmith MCP server is already configured
    if claude mcp list 2>/dev/null | grep -q "LangSmith"; then
        echo "✅ LangSmith MCP server already configured"
        return 0
    fi

    # Read API key from environment variable
    api_key="${LANGSMITH_API_KEY:-your_langsmith_api_key}"

    # Warn if using placeholder value
    if [ "$api_key" = "your_langsmith_api_key" ]; then
        echo "⚠️  No LANGSMITH_API_KEY found in environment"
        echo "   Using placeholder value. You'll need to update it later."
    fi

    # Add LangSmith MCP server using CLI
    echo "Adding LangSmith MCP server..."
    if claude mcp add --transport stdio "LangSmith" \
        --env LANGSMITH_API_KEY="$api_key" \
        -- uvx langsmith-mcp-server; then
        echo "✅ LangSmith MCP server added successfully"
        if [ "$api_key" = "your_langsmith_api_key" ]; then
            echo "📝 Remember to update the environment variable:"
            echo "   Run: claude mcp get 'LangSmith API MCP Server' to see configuration"
            echo "   You'll need to update LANGSMITH_API_KEY"
        fi
    else
        echo "⚠️  Warning: Failed to add LangSmith MCP server"
        echo "   You can try manually: claude mcp add --transport stdio 'LangSmith API MCP Server' \\"
        echo "     --env LANGSMITH_API_KEY=your_key -- uvx langsmith-mcp-server"
    fi
}

# Setup Glean MCP server configuration
# Note: Glean MCP requires authentication. You'll need to authenticate after installation.
# Usage: setup_glean_mcp
setup_glean_mcp() {
    echo "Setting up Glean MCP server..."

    # Check if Claude Code is available
    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping Glean MCP setup."
        echo "   Install Claude Code first, then run: claude mcp add ..."
        return 1
    fi

    # Check if Glean MCP server is already configured
    if claude mcp list 2>/dev/null | grep -q "glean_default"; then
        echo "✅ Glean MCP server already configured"
        return 0
    fi

    # Add Glean MCP server using CLI
    echo "Adding Glean MCP server..."
    if claude mcp add glean_default https://vanta-be.glean.com/mcp/default \
        --transport http \
        --scope user; then
        echo "✅ Glean MCP server added successfully"
        echo "📝 Note: Glean MCP requires authentication. You'll need to authenticate to use it."
        echo "   See: https://docs.glean.com/user-guide/mcp/usage"
    else
        echo "⚠️  Warning: Failed to add Glean MCP server"
        echo "   You can try manually: claude mcp add glean_default https://vanta-be.glean.com/mcp/default \\"
        echo "     --transport http --scope user"
        echo "   See: https://docs.glean.com/user-guide/mcp/usage"
    fi
}

# Install a tool from a URL if not already present
# Usage: install_from_url <display_name> <command_name> <install_url>
install_from_url() {
    display_name=$1
    command_name=$2
    install_url=$3

    echo "Checking for $display_name..."
    if command -v "$command_name" >/dev/null 2>&1; then
        echo "✅ $display_name already installed"
        return 0
    fi

    echo "Installing $display_name..."
    if command -v bash >/dev/null 2>&1; then
        runner="bash"
    else
        runner="sh"
    fi

    if curl -fsSL "$install_url" | "$runner"; then
        echo "✅ $display_name installed successfully"
    else
        echo "⚠️  Warning: $display_name installation failed"
        echo "   Try manually: curl -fsSL $install_url | $runner"
    fi
}

# Create symlinks to dot files
create_symlinks() {
    script_dir=$(dirname "$(readlink -f "$0")")

    # Files to symlink (exclude .example files)
    for file in "$script_dir"/.*; do
        [ -f "$file" ] || continue
        name=$(basename "$file")
        
        # Skip example files, git metadata, and macOS metadata
        case "$name" in
            *.example|.git|.DS_Store) continue ;;
        esac

        echo "Creating symlink to $name in home directory."
        rm -rf "$HOME/$name"
        ln -s "$file" "$HOME/$name"
    done
}

# Setup Cursor IDE configuration
# Symlinks settings, keybindings, snippets, and skills from Dotfiles
setup_cursor() {
    echo "Setting up Cursor IDE configuration..."

    # Skip if Cursor is not installed (e.g., in Gitpod/Codespaces)
    if ! command -v cursor >/dev/null 2>&1 && [ ! -d "/Applications/Cursor.app" ] && [ ! -d "$HOME/.cursor" ]; then
        echo "ℹ️  Cursor not installed, skipping Cursor setup."
        return 0
    fi

    script_dir=$(dirname "$(readlink -f "$0")")
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

    # Symlink skills directory
    if [ -d "$cursor_dotfiles/skills" ]; then
        echo "Linking Cursor agent skills..."
        rm -rf "$cursor_home_dir/skills-cursor"
        ln -s "$cursor_dotfiles/skills" "$cursor_home_dir/skills-cursor"
        echo "✅ agent skills linked"
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
    script_dir=$(dirname "$(readlink -f "$0")")

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

# Setup work-specific tools (Glean MCP, etc.)
# Only runs if WORK_MACHINE=1 or user confirms interactively
setup_work_tools() {
    if [ "$WORK_MACHINE" = "1" ]; then
        echo "Work machine detected (WORK_MACHINE=1). Setting up work tools..."
        setup_glean_mcp
    elif [ -t 0 ]; then
        printf "Setup work-specific tools (Glean MCP)? [y/N] "
        read -r is_work
        if [ "$is_work" = "y" ] || [ "$is_work" = "Y" ]; then
            setup_glean_mcp
        else
            echo "Skipping work-specific tools."
        fi
    else
        echo "Skipping work-specific tools (non-interactive, WORK_MACHINE not set)."
    fi
}

# Install packages (Linux only)
if [ "$OS" = "linux" ]; then
    install_from_apt "lua5.4"
    install_from_apt "gh"
fi

create_symlinks

# Install tools from URLs
install_from_url "uv" "uv" "https://astral.sh/uv/install.sh"
install_from_url "Claude Code" "claude" "https://claude.ai/install.sh"

# Setup Cursor IDE
setup_cursor
install_cursor_extensions

# Setup MCP servers
setup_langsmith_mcp

# Setup work-specific tools (conditional)
setup_work_tools
