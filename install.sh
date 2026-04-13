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
        echo "⚠️  Warning: 'claude' command not found. Skipping Claude LangSmith MCP CLI setup."
        echo "   Install Claude Code first, then run: claude mcp add ..."
        merge_cursor_mcp_langsmith
        return 1
    fi

    # Check if LangSmith MCP server is already configured
    if claude mcp list 2>/dev/null | grep -q "LangSmith"; then
        echo "✅ LangSmith MCP server already configured (Claude)"
        merge_cursor_mcp_langsmith
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
    if claude mcp add --transport stdio --scope user "LangSmith" \
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

    merge_cursor_mcp_langsmith
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

# Merge mcpServers from a fragment JSON into ~/.cursor/mcp.json (adds only missing server names).
# Fragment must be {"mcpServers": {...}} or a flat object of server name -> config.
# Usage: merge_cursor_mcp_fragment <path_to_json>
merge_cursor_mcp_fragment() {
    fragment_path=$1
    if ! command -v python3 >/dev/null 2>&1; then
        echo "⚠️  Python3 not found; skipping Cursor MCP merge ($fragment_path)"
        return 1
    fi
    if [ ! -f "$fragment_path" ]; then
        echo "⚠️  Cursor MCP fragment not found: $fragment_path"
        return 1
    fi
    python3 -c "
import json, os, sys
fragment_path = sys.argv[1]
cursor_dir = os.path.expanduser('~/.cursor')
os.makedirs(cursor_dir, exist_ok=True)
path = os.path.join(cursor_dir, 'mcp.json')
with open(fragment_path) as f:
    frag = json.load(f)
servers = frag['mcpServers'] if isinstance(frag, dict) and 'mcpServers' in frag else frag
if not isinstance(servers, dict):
    sys.exit('Invalid fragment: expected object or mcpServers object')
data = {}
if os.path.isfile(path):
    with open(path) as f:
        data = json.load(f)
ms = data.setdefault('mcpServers', {})
added = [k for k in servers if k not in ms]
for k, v in servers.items():
    if k not in ms:
        ms[k] = v
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
if added:
    print('✅ Cursor MCP: added', ', '.join(added))
else:
    print('✅ Cursor MCP: already had', ', '.join(servers.keys()))
" "$fragment_path" || return 1
}

# Merge LangSmith MCP entry for Cursor (from repo fragment).
merge_cursor_mcp_langsmith() {
    script_dir=$(dirname "$(readlink -f "$0")")
    f="$script_dir/cursor/mcp-servers-personal.json"
    if [ ! -f "$f" ]; then
        return 0
    fi
    echo "Merging LangSmith into Cursor MCP config..."
    merge_cursor_mcp_fragment "$f" || true
}

# Add Datadog MCP to ~/.cursor/mcp.json using env placeholders (same vars as Claude setup).
merge_cursor_mcp_datadog() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi
    python3 <<'PY'
import json, os
path = os.path.expanduser("~/.cursor/mcp.json")
datadog = {
    "command": "npx",
    "args": [
        "datadog-mcp-server",
        "--apiKey", "${DATADOG_LOCAL_DEVELOPMENT_KEY_2}",
        "--appKey", "${DATADOG_APP_KEY}",
        "--site", "datadoghq.com",
        "--logsSite", "logs.datadoghq.com",
        "--metricsSite", "datadoghq.com",
    ],
}
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.isfile(path):
    with open(path) as f:
        data = json.load(f)
ms = data.setdefault("mcpServers", {})
if "datadog" not in ms:
    ms["datadog"] = datadog
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print("✅ Cursor MCP: added datadog")
else:
    print("✅ Cursor MCP: datadog already present")
PY
}

# Merge user MCP servers from Claude Code (~/.claude.json top-level mcpServers) into ~/.cursor/mcp.json.
# Strips Claude-only fields (e.g. type). Only adds/updates entries present in Claude; does not remove Cursor-only servers.
# Usage: sync_cursor_mcp_from_claude
sync_cursor_mcp_from_claude() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "⚠️  Python3 not found; skipping Claude → Cursor MCP sync"
        return 1
    fi
    claude_json="${HOME}/.claude.json"
    if [ ! -f "$claude_json" ]; then
        return 0
    fi
    script_dir=$(dirname "$(readlink -f "$0")")
    python3 "$script_dir/scripts/sync_cursor_mcp_from_claude.py" || return $?
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

# Setup Claude Dev tasks configuration
# Symlinks cloudev/tasks.json to ~/.cloudev/tasks.json
setup_cloudev_tasks() {
    script_dir=$(dirname "$(readlink -f "$0")")
    source_tasks="$script_dir/cloudev/tasks.json"
    target_dir="$HOME/.cloudev"
    target_tasks="$target_dir/tasks.json"

    if [ ! -f "$source_tasks" ]; then
        echo "ℹ️  cloudev/tasks.json not found, skipping Claude Dev tasks setup."
        return 0
    fi

    mkdir -p "$target_dir"
    rm -f "$target_tasks"
    ln -s "$source_tasks" "$target_tasks"
    echo "✅ Linked Claude Dev tasks: $target_tasks -> $source_tasks"
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

# Setup Datadog MCP server configuration (user scope — always available)
# Reads API keys from environment variables (DATADOG_LOCAL_DEVELOPMENT_KEY_2, DATADOG_APP_KEY)
setup_datadog_mcp() {
    echo "Setting up Datadog MCP server..."

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping Datadog MCP setup."
        return 1
    fi

    if claude mcp list 2>/dev/null | grep -q "datadog"; then
        echo "✅ Datadog MCP server already configured"
        return 0
    fi

    api_key="${DATADOG_LOCAL_DEVELOPMENT_KEY_2:-}"
    app_key="${DATADOG_APP_KEY:-}"

    if [ -z "$api_key" ] || [ -z "$app_key" ]; then
        echo "⚠️  DATADOG_LOCAL_DEVELOPMENT_KEY_2 or DATADOG_APP_KEY not set"
        echo "   Skipping Datadog MCP setup. Set these env vars and re-run."
        return 1
    fi

    echo "Adding Datadog MCP server..."
    if claude mcp add --transport stdio --scope user "datadog" \
        -- npx datadog-mcp-server \
        --apiKey "$api_key" \
        --appKey "$app_key" \
        --site datadoghq.com \
        --logsSite logs.datadoghq.com \
        --metricsSite datadoghq.com; then
        echo "✅ Datadog MCP server added successfully"
    else
        echo "⚠️  Warning: Failed to add Datadog MCP server"
    fi
}

# Install superpowers plugin for Claude Code (user scope — always available)
setup_superpowers_plugin() {
    echo "Setting up superpowers plugin for Claude Code..."

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping superpowers plugin setup."
        return 1
    fi

    if claude plugin list 2>/dev/null | grep -q "superpowers"; then
        echo "✅ superpowers plugin already installed"
        return 0
    fi

    # Register the superpowers marketplace if not already known
    if ! claude plugin marketplace list 2>/dev/null | grep -q "superpowers-marketplace"; then
        echo "Adding superpowers-marketplace..."
        if ! claude plugin marketplace add obra/superpowers-marketplace 2>/dev/null; then
            echo "⚠️  Warning: Failed to add superpowers-marketplace"
            return 1
        fi
    fi

    echo "Installing superpowers plugin..."
    if claude plugin install superpowers@superpowers-marketplace 2>/dev/null; then
        echo "✅ superpowers plugin installed"
    else
        echo "⚠️  Warning: Failed to install superpowers plugin"
        return 1
    fi
}

# Setup Claude Code config: user-level CLAUDE.md and skills
setup_claude_config() {
    script_dir=$(dirname "$(readlink -f "$0")")
    claude_dir="$HOME/.claude"
    mkdir -p "$claude_dir"

    # Symlink user-level CLAUDE.md (work scope only)
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$script_dir/claude/CLAUDE.md" ]; then
        rm -f "$claude_dir/CLAUDE.md"
        ln -s "$script_dir/claude/CLAUDE.md" "$claude_dir/CLAUDE.md"
        echo "✅ Claude Code CLAUDE.md linked (work)"
    fi

    # Symlink skills (work scope only): claude/skills + shared-skills (both tools via install)
    if [ "$WORK_MACHINE" = "1" ]; then
        mkdir -p "$claude_dir/skills"
        for source_skills in "$script_dir/claude/skills" "$script_dir/shared-skills"; do
            if [ ! -d "$source_skills" ]; then
                continue
            fi
            for skill_dir in "$source_skills"/*/; do
                [ -d "$skill_dir" ] || continue
                name=$(basename "$skill_dir")
                rm -rf "$claude_dir/skills/$name"
                ln -s "$skill_dir" "$claude_dir/skills/$name"
            done
        done
        echo "✅ Claude Code skills linked (work)"
    fi
}

# Install Tailscale CLI
# Uses the official install script which adds the apt repo and installs.
# In containers without systemd, starts tailscaled with userspace networking.
# Usage: install_tailscale
install_tailscale() {
    echo "Checking for Tailscale..."

    if command -v tailscale >/dev/null 2>&1; then
        echo "✅ Tailscale already installed ($(tailscale version | head -1))"
    else
        echo "Installing Tailscale..."
        if curl -fsSL https://tailscale.com/install.sh | sh; then
            echo "✅ Tailscale installed successfully"
        else
            echo "⚠️  Warning: Tailscale installation failed"
            echo "   Try manually: https://tailscale.com/download"
            return 1
        fi
    fi

    # In containers without systemd, start tailscaled manually
    if ! tailscale status >/dev/null 2>&1; then
        if ! pidof systemd >/dev/null 2>&1; then
            echo "Starting tailscaled (no systemd detected)..."
            sudo tailscaled --tun=userspace-networking \
                --state=/var/lib/tailscale/tailscaled.state \
                --socket=/run/tailscale/tailscaled.sock > /tmp/tailscaled.log 2>&1 &
            echo "✅ tailscaled started with userspace networking (pid $!)"
        else
            sudo systemctl start tailscaled
        fi
    fi
}

# Install Datadog pup CLI from GitHub releases
# Downloads the latest pre-built binary for the current OS/arch
# Usage: install_pup_cli
install_pup_cli() {
    echo "Checking for Datadog pup CLI..."

    if command -v pup >/dev/null 2>&1; then
        echo "✅ Datadog pup CLI already installed"
        return 0
    fi

    echo "Installing Datadog pup CLI..."

    # Determine OS and architecture for download
    case "$(uname -s)" in
        Darwin*) pup_os="Darwin" ;;
        Linux*)  pup_os="Linux" ;;
        *)
            echo "⚠️  Unsupported OS for pup. Try: https://github.com/datadog-labs/pup"
            return 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) pup_arch="x86_64" ;;
        arm64|aarch64) pup_arch="arm64" ;;
        *)
            echo "⚠️  Unsupported architecture for pup: $(uname -m)"
            return 1
            ;;
    esac

    # Fetch latest version tag from GitHub
    pup_version=$(gh release view --repo datadog-labs/pup --json tagName -q .tagName 2>/dev/null | sed 's/^v//')
    if [ -z "$pup_version" ]; then
        echo "⚠️  Could not determine latest pup version"
        echo "   Try manually: https://github.com/datadog-labs/pup/releases"
        return 1
    fi

    pup_tarball="pup_${pup_version}_${pup_os}_${pup_arch}.tar.gz"
    pup_url="https://github.com/datadog-labs/pup/releases/download/v${pup_version}/${pup_tarball}"
    pup_install_dir="$HOME/.local/bin"

    mkdir -p "$pup_install_dir"

    tmpdir=$(mktemp -d)
    if curl -fsSL "$pup_url" -o "$tmpdir/$pup_tarball" && \
       tar -xzf "$tmpdir/$pup_tarball" -C "$tmpdir" && \
       install -m 755 "$tmpdir/pup" "$pup_install_dir/pup"; then
        rm -rf "$tmpdir"
        echo "✅ Datadog pup CLI installed to $pup_install_dir/pup"
    else
        rm -rf "$tmpdir"
        echo "⚠️  Warning: Datadog pup CLI installation failed"
        echo "   Try manually: https://github.com/datadog-labs/pup/releases"
        return 1
    fi
}

# Install Netlify CLI globally via npm
install_netlify_cli() {
    echo "Checking for Netlify CLI..."

    if command -v netlify >/dev/null 2>&1; then
        echo "✅ Netlify CLI already installed"
        return 0
    fi

    echo "Installing Netlify CLI..."
    if npm install -g netlify-cli; then
        echo "✅ Netlify CLI installed successfully"
    else
        echo "⚠️  Warning: Netlify CLI installation failed"
        echo "   Try manually: npm install -g netlify-cli"
        return 1
    fi
}

# Setup Netlify MCP server (user scope — work only)
setup_netlify_mcp() {
    echo "Setting up Netlify MCP server..."

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping Netlify MCP setup."
        return 1
    fi

    if claude mcp list 2>/dev/null | grep -q "netlify"; then
        echo "✅ Netlify MCP server already configured"
        return 0
    fi

    echo "Adding Netlify MCP server..."
    if claude mcp add --scope user "netlify" \
        -- npx -y @netlify/mcp; then
        echo "✅ Netlify MCP server added successfully"
    else
        echo "⚠️  Warning: Failed to add Netlify MCP server"
        echo "   Try manually: claude mcp add netlify npx -- -y @netlify/mcp"
    fi
}

# Setup MongoDB MCP server (user scope — always available, connect at runtime via /connect-mongo)
setup_mongodb_mcp() {
    echo "Setting up MongoDB MCP server..."

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping MongoDB MCP setup."
        return 1
    fi

    if claude mcp list 2>/dev/null | grep -q "mongodb"; then
        echo "✅ MongoDB MCP server already configured"
        return 0
    fi

    echo "Adding MongoDB MCP server..."
    if claude mcp add --transport stdio --scope user "mongodb" \
        -- npx -y mongodb-mcp-server; then
        echo "✅ MongoDB MCP server added (use /connect-mongo to connect)"
    else
        echo "⚠️  Warning: Failed to add MongoDB MCP server"
    fi
}

# Setup work-specific tools (Glean MCP, Datadog MCP, MongoDB MCP, etc.)
# Only runs if WORK_MACHINE=1 or user confirms interactively
setup_work_tools() {
    if [ "$WORK_MACHINE" = "1" ]; then
        echo "Work machine detected (WORK_MACHINE=1). Setting up work tools..."
        setup_glean_mcp
        setup_datadog_mcp
        setup_mongodb_mcp
        install_netlify_cli
        setup_netlify_mcp
        merge_cursor_work_mcp_entries
    elif [ -t 0 ]; then
        printf "Setup work-specific tools (Glean, Datadog, MongoDB, Netlify MCP)? [y/N] "
        read -r is_work
        if [ "$is_work" = "y" ] || [ "$is_work" = "Y" ]; then
            setup_glean_mcp
            setup_datadog_mcp
            setup_mongodb_mcp
            install_netlify_cli
            setup_netlify_mcp
            merge_cursor_work_mcp_entries
        else
            echo "Skipping work-specific tools."
        fi
    else
        echo "Skipping work-specific tools (non-interactive, WORK_MACHINE not set). Includes: Glean, Datadog, MongoDB, Netlify."
    fi
}

# Merge work MCP servers into ~/.cursor/mcp.json (Glean, MongoDB, Netlify; Datadog if env vars set).
merge_cursor_work_mcp_entries() {
    script_dir=$(dirname "$(readlink -f "$0")")
    work_fragment="$script_dir/cursor/mcp-servers-work.json"
    if [ -f "$work_fragment" ]; then
        echo "Merging work MCP servers into Cursor config..."
        merge_cursor_mcp_fragment "$work_fragment" || true
    fi
    api_key="${DATADOG_LOCAL_DEVELOPMENT_KEY_2:-}"
    app_key="${DATADOG_APP_KEY:-}"
    if [ -n "$api_key" ] && [ -n "$app_key" ]; then
        merge_cursor_mcp_datadog || true
    fi
}

# Install LangSmith CLI
# Usage: install_langsmith_cli
install_langsmith_cli() {
    echo "Checking for LangSmith CLI..."

    if command -v langsmith >/dev/null 2>&1; then
        echo "✅ LangSmith CLI already installed"
        return 0
    fi

    # Prefer uv (already installed above), then pipx, then pip as fallback
    if command -v uv >/dev/null 2>&1; then
        echo "Installing LangSmith CLI with uv..."
        if uv tool install --upgrade "langsmith[cli]"; then
            echo "✅ LangSmith CLI installed successfully"
            return 0
        fi
    fi

    if command -v pipx >/dev/null 2>&1; then
        echo "Installing LangSmith CLI with pipx..."
        if pipx install --force "langsmith[cli]"; then
            echo "✅ LangSmith CLI installed successfully"
            return 0
        fi
    fi

    if command -v python3 >/dev/null 2>&1; then
        echo "Installing LangSmith CLI with pip..."
        if python3 -m pip install --user -U "langsmith[cli]"; then
            echo "✅ LangSmith CLI installed successfully"
            return 0
        fi
    fi

    echo "⚠️  Warning: Failed to install LangSmith CLI"
    echo "   Try manually: uv tool install 'langsmith[cli]'"
    return 1
}

# Install packages (Linux only)
if [ "$OS" = "linux" ]; then
    install_from_apt "lua5.4"
    install_from_apt "gh"
fi

create_symlinks
setup_cloudev_tasks

# Install tools from URLs
install_from_url "uv" "uv" "https://astral.sh/uv/install.sh"
install_from_url "Claude Code" "claude" "https://claude.ai/install.sh"
install_langsmith_cli
if [ "$WORK_MACHINE" = "1" ]; then
    install_tailscale
    install_pup_cli
fi

# Setup Cursor IDE
setup_cursor
install_cursor_extensions

# Setup MCP servers
setup_langsmith_mcp

# Install LangSmith skills for Claude Code
if command -v claude >/dev/null 2>&1; then
    echo "Installing LangSmith skills for Claude Code..."
    npx skills add langchain-ai/langsmith-skills --agent claude-code --skill '*' --yes --global 2>/dev/null \
        && echo "✅ LangSmith skills installed (Claude Code)" \
        || echo "⚠️  LangSmith skills installation failed for Claude Code (can retry manually)"
fi

# Install LangSmith skills for Cursor (same package; agent-specific install path)
if command -v cursor >/dev/null 2>&1 || [ -d "/Applications/Cursor.app" ] || [ -d "$HOME/.cursor" ]; then
    echo "Installing LangSmith skills for Cursor..."
    npx skills add langchain-ai/langsmith-skills --agent cursor --skill '*' --yes --global 2>/dev/null \
        && echo "✅ LangSmith skills installed (Cursor)" \
        || echo "⚠️  LangSmith skills installation failed for Cursor (can retry manually)"
fi

# Setup Claude Code config and commands
setup_claude_config
setup_superpowers_plugin

# Setup work-specific tools (conditional)
setup_work_tools

# Align Cursor MCP with Claude Code user config (after all claude mcp add steps)
sync_cursor_mcp_from_claude || true
