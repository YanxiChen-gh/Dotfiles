#!/bin/sh

# Detect OS
case "$(uname -s)" in
    Darwin*) OS="macos" ;;
    Linux*)  OS="linux" ;;
    *)       OS="unknown" ;;
esac

# Set default workspace directory (used by Gas Town init)
WORKSPACES_DIR="${WORKSPACES_DIR:-/workspaces/workspaces}"
mkdir -p "$WORKSPACES_DIR"

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

# Default the interactive shell to zsh in Vanta's Ona remote dev env.
#
# Ona CDEs SSH in via `exec -l $SHELL -i` with $SHELL=/bin/bash, and a
# container's /etc/passwd can reset on rebuild, so `chsh` alone isn't reliable.
# We add an idempotent, runtime-gated guard to ~/.bashrc that hands interactive
# bash sessions over to zsh whenever IS_ON_ONA is set (harmless on a personal
# machine, where the variable is absent), and best-effort `chsh` when this
# installer is itself running inside Ona.
setup_ona_default_shell() {
    bashrc="$HOME/.bashrc"
    marker="# >>> dotfiles: default to zsh on Ona >>>"

    if [ ! -f "$bashrc" ] || ! grep -qF "$marker" "$bashrc"; then
        cat >> "$bashrc" <<'EOF'

# >>> dotfiles: default to zsh on Ona >>>
# In Vanta's Ona CDE, hand interactive bash sessions over to zsh.
case "$-" in
    *i*)
        if [ -n "$IS_ON_ONA" ] && [ -z "$ZSH_VERSION" ]; then
            _zsh=$(command -v zsh 2>/dev/null)
            if [ -n "$_zsh" ]; then
                export SHELL="$_zsh"
                exec "$_zsh" -l
            fi
            unset _zsh
        fi
        ;;
esac
# <<< dotfiles: default to zsh on Ona <<<
EOF
        echo "✅ Added zsh-on-Ona guard to $bashrc"
    fi

    # When installing inside Ona, ensure zsh exists and set it as the login shell.
    if [ -n "$IS_ON_ONA" ]; then
        if ! command -v zsh >/dev/null 2>&1 && [ "$OS" = "linux" ]; then
            install_from_apt "zsh"
        fi
        zsh_path=$(command -v zsh 2>/dev/null)
        if [ -n "$zsh_path" ] && [ "$(basename "${SHELL:-}")" != "zsh" ]; then
            # IMPORTANT: chsh prompts for a PAM password; without </dev/null it blocks
            # forever during non-interactive provisioning (postCreate hang). Fail fast
            # instead — the ~/.bashrc guard above already hands interactive shells to zsh.
            if chsh -s "$zsh_path" </dev/null 2>/dev/null; then
                echo "✅ Login shell set to $zsh_path"
            else
                echo "ℹ️  Could not chsh to zsh; ~/.bashrc will exec zsh on login instead."
            fi
        fi
    fi
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

    # Symlink user-level CLAUDE.md + RTK.md (work scope only)
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$script_dir/claude/CLAUDE.md" ]; then
        rm -f "$claude_dir/CLAUDE.md"
        ln -s "$script_dir/claude/CLAUDE.md" "$claude_dir/CLAUDE.md"
        echo "✅ Claude Code CLAUDE.md linked (work)"
    fi
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$script_dir/claude/RTK.md" ]; then
        rm -f "$claude_dir/RTK.md"
        ln -s "$script_dir/claude/RTK.md" "$claude_dir/RTK.md"
        echo "✅ Claude Code RTK.md linked (work)"
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

    # Register the comment-bar PostToolUse hook (work scope): nudges the model to apply the
    # comment bar after JS/TS edits, since current models over-comment by default. Idempotent
    # (deduped on the script name). Kill switch + retirement trigger live in the script itself.
    hook_script="$script_dir/claude/hooks/comment-self-check.sh"
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$hook_script" ]; then
        chmod +x "$hook_script" 2>/dev/null || true
        COMMENT_HOOK_CMD="bash $hook_script" python3 - "$claude_dir/settings.json" <<'PY'
import json, os, sys

path, cmd = sys.argv[1], os.environ["COMMENT_HOOK_CMD"]
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

post = cfg.setdefault("hooks", {}).setdefault("PostToolUse", [])
present = any(
    "comment-self-check.sh" in h.get("command", "")
    for entry in post
    for h in entry.get("hooks", [])
)
if not present:
    post.append({"matcher": "Write|Edit", "hooks": [{"type": "command", "command": cmd}]})
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("registered comment-bar PostToolUse hook")
else:
    print("comment-bar hook already registered")
PY
        echo "✅ Claude Code comment-bar hook registered (work)"
    fi

    # Register the verify-gate PreToolUse(Bash) hook (work scope): blocks `gh pr create`
    # when the PR body lacks verification evidence + an independent-review/grading section
    # (Trust L2→L3 lever). Idempotent (deduped on the script name). Fail-open + kill switch
    # (VERIFY_GATE=off) + retirement trigger live in the script itself.
    vg_hook="$script_dir/claude/hooks/verify-gate-pretooluse.sh"
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$vg_hook" ]; then
        chmod +x "$vg_hook" "$script_dir/claude/hooks/verify-gate-check.py" 2>/dev/null || true
        VERIFY_HOOK_CMD="bash $vg_hook" python3 - "$claude_dir/settings.json" <<'PY'
import json, os, sys

path, cmd = sys.argv[1], os.environ["VERIFY_HOOK_CMD"]
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

pre = cfg.setdefault("hooks", {}).setdefault("PreToolUse", [])
present = any(
    "verify-gate-pretooluse.sh" in h.get("command", "")
    for entry in pre
    for h in entry.get("hooks", [])
)
if not present:
    pre.append({"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]})
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("registered verify-gate PreToolUse hook")
else:
    print("verify-gate hook already registered")
PY
        echo "✅ Claude Code verify-gate hook registered (work)"
    fi

    # Register the pr-authoring gate PreToolUse(Bash) hook (work scope): blocks `gh pr create`
    # / `gh pr edit --body` when an LLM judge (claude -p) grades the body as bloated against
    # pr-authoring.md, so the guide lands on the first draft instead of a post-hoc /simplify-pr
    # cleanup (Spec lever). Idempotent (deduped on the script name). Fail-open + kill switch
    # (PR_AUTHORING_GATE=off) + retirement trigger live in the script itself.
    pag_hook="$script_dir/claude/hooks/pr-authoring-gate-pretooluse.sh"
    if [ "$WORK_MACHINE" = "1" ] && [ -f "$pag_hook" ]; then
        chmod +x "$pag_hook" "$script_dir/claude/hooks/pr-authoring-gate-check.py" 2>/dev/null || true
        PAG_HOOK_CMD="bash $pag_hook" python3 - "$claude_dir/settings.json" <<'PY'
import json, os, sys

path, cmd = sys.argv[1], os.environ["PAG_HOOK_CMD"]
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

pre = cfg.setdefault("hooks", {}).setdefault("PreToolUse", [])
present = any(
    "pr-authoring-gate-pretooluse.sh" in h.get("command", "")
    for entry in pre
    for h in entry.get("hooks", [])
)
if not present:
    pre.append({"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]})
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("registered pr-authoring gate PreToolUse hook")
else:
    print("pr-authoring gate hook already registered")
PY
        echo "✅ Claude Code pr-authoring gate hook registered (work)"
    fi
}

# Symlink Codex global instructions and RTK reference.
setup_codex_config() {
    script_dir=$(dirname "$(readlink -f "$0")")
    codex_dir="$HOME/.codex"
    mkdir -p "$codex_dir"

    if [ -f "$script_dir/codex-instructions.md" ]; then
        rm -f "$codex_dir/AGENTS.md"
        ln -s "$script_dir/codex-instructions.md" "$codex_dir/AGENTS.md"
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

# Install RTK and enable for Claude Code, OpenAI Codex (GPT), and Cursor.
# Claude: PreToolUse hook in ~/.claude/settings.json
# Cursor: preToolUse hook in cursor/hooks.json (symlinked to ~/.cursor/hooks.json)
# Codex: AGENTS.md + RTK.md symlinks (~/.codex/); agents prefix shell commands with rtk
setup_rtk() {
    echo "Setting up RTK (token-optimized shell output)..."

    install_from_url "RTK" "rtk" "https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"

    if ! command -v rtk >/dev/null 2>&1; then
        echo "⚠️  RTK binary not found; skipping agent hook registration"
        return 1
    fi

    # Opt out of telemetry unless explicitly enabled by the user.
    export RTK_TELEMETRY_DISABLED=1

    # Claude Code — automatic bash rewrite via settings.json hook
    if command -v claude >/dev/null 2>&1; then
        if rtk init -g --hook-only --auto-patch 2>/dev/null; then
            echo "✅ RTK hook registered for Claude Code"
        else
            echo "⚠️  RTK Claude Code hook registration failed (run: rtk init -g --hook-only --auto-patch)"
        fi
    else
        echo "ℹ️  Claude Code not installed; skipping RTK Claude hook"
    fi

    # Cursor — automatic shell rewrite via hooks.json (versioned in dotfiles)
    if rtk init -g --agent cursor --hook-only --auto-patch 2>/dev/null; then
        echo "✅ RTK hook verified for Cursor"
    elif [ -f "$HOME/.cursor/hooks.json" ]; then
        echo "✅ RTK Cursor hook present (cursor/hooks.json)"
    else
        echo "⚠️  RTK Cursor hook not configured (re-run install or: rtk init -g --agent cursor --hook-only --auto-patch)"
    fi

    # OpenAI Codex (GPT) — AGENTS.md + RTK.md (instruction-based; no bash hook API)
    setup_codex_config
    if [ -f "$HOME/.codex/AGENTS.md" ] && [ -f "$HOME/.codex/RTK.md" ]; then
        echo "✅ RTK instructions linked for OpenAI Codex (GPT)"
    else
        echo "⚠️  Codex RTK config incomplete (expected ~/.codex/AGENTS.md and RTK.md)"
    fi

    echo "✅ RTK setup complete (rtk gain for savings stats)"
}

# Install the agent-maturity engine. It lives in its own PUBLIC repo
# (github.com/YanxiChen-gh/agent-maturity); the engine's bootstrap.sh does all the heavy
# lifting (clone-or-pull → install.sh → skills + scope-gate hooks + `li` + env). So this is
# just the one-liner — same line any teammate puts in their own dotfiles. Data stays private.
setup_agent_maturity() {
    echo "Setting up agent-maturity engine..."
    local boot="${AGENT_MATURITY_BOOTSTRAP_URL:-https://raw.githubusercontent.com/YanxiChen-gh/agent-maturity/main/bootstrap.sh}"
    local data_repo="${AGENT_MATURITY_DATA_REPO:-YanxiChen-gh/agent-maturity-data}"
    if curl -fsSL "$boot" | bash -s -- --data-repo "$data_repo" \
         --name "$(git config --global user.name)" --email "$(git config --global user.email)" >/dev/null; then
        echo "✅ agent-maturity installed (via engine bootstrap)"
    else
        echo "⚠️  agent-maturity install failed (curl $boot | bash)"
    fi
}

# Enable Vanta AI Platform Claude Code plugin and sync its skills to Cursor.
setup_vanta_ai_platform_plugin() {
    if [ "$WORK_MACHINE" != "1" ]; then
        return 0
    fi

    obsidian_root="${OBSIDIAN_ROOT:-/workspaces/obsidian}"
    if [ ! -d "$obsidian_root/.claude/plugins/ai-platform-team" ]; then
        echo "ℹ️  obsidian checkout not found; skipping AI Platform plugin setup"
        return 0
    fi

    echo "Setting up Vanta AI Platform plugin for Claude Code and Cursor..."

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$HOME/.claude/settings.json" <<'PY'
import json
import os
import sys

path = os.path.expanduser(sys.argv[1])
os.makedirs(os.path.dirname(path), exist_ok=True)

data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

data.setdefault("enabledPlugins", {})["ai-platform-team@obsidian-local"] = True

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
        echo "✅ AI Platform plugin enabled for Claude Code"
    else
        echo "⚠️  Python3 not found; skipping Claude Code plugin enablement"
    fi

    script_dir=$(dirname "$(readlink -f "$0")")
    sync_script="$script_dir/cc-sync-to-cursor-workspace.sh"
    if [ -x "$sync_script" ]; then
        "$sync_script" "$obsidian_root" || true
    else
        echo "⚠️  Cursor skill sync script not found or not executable: $sync_script"
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

    # Install pup skills for AI coding assistants
    echo "Installing pup skills..."
    if pup skills install --target-agent claude-code 2>/dev/null; then
        echo "✅ Datadog pup skills installed"
    else
        echo "⚠️  Warning: pup skills install failed (may need auth first: pup auth login)"
    fi
}

# Ensure Node.js and npm are available
# Codespaces typically have node pre-installed; this is a fallback
install_node_if_missing() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        echo "✅ Node.js $(node --version) and npm $(npm --version) already installed"
        return 0
    fi

    echo "Installing Node.js via NodeSource..."
    if curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && \
       sudo apt-get install -y nodejs; then
        echo "✅ Node.js installed: $(node --version), npm $(npm --version)"
    else
        echo "⚠️  Warning: Node.js installation failed"
        echo "   Try manually: https://nodejs.org/en/download"
        return 1
    fi
}

# Install Gas Town (gt) CLI and its dependencies
# Installs: libicu-dev, tmux (apt), Dolt (binary), node (if missing), gt (npm)
# Then initializes gt and Dolt for the workspace if not already done
install_gastown() {
    echo "Checking for Gas Town (gt) CLI..."

    # Install system dependencies (libicu-dev for beads, tmux for Mayor sessions)
    install_from_apt "libicu-dev"
    install_from_apt "tmux"

    # Install Dolt if not present
    if command -v dolt >/dev/null 2>&1; then
        echo "✅ Dolt already installed"
    else
        echo "Installing Dolt..."
        if curl -L https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash; then
            echo "✅ Dolt installed successfully"
        else
            echo "⚠️  Warning: Dolt installation failed"
            echo "   Try manually: curl -L https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash"
        fi
    fi

    # Ensure npm is available before installing gt
    install_node_if_missing || return 1

    # Install gt CLI via npm
    if command -v gt >/dev/null 2>&1; then
        echo "✅ Gas Town (gt) CLI already installed"
    else
        echo "Installing Gas Town (gt) CLI..."
        if sudo npm install -g @gastown/gt; then
            echo "✅ Gas Town (gt) CLI installed successfully"
        else
            echo "⚠️  Warning: Gas Town (gt) CLI installation failed"
            echo "   Try manually: sudo npm install -g @gastown/gt"
            return 1
        fi
    fi

    # Initialize gt workspace and Dolt if not already done
    if command -v gt >/dev/null 2>&1 && [ -n "$WORKSPACES_DIR" ]; then
        if [ ! -d "$WORKSPACES_DIR/.beads" ]; then
            echo "Initializing Gas Town workspace at $WORKSPACES_DIR..."
            gt install "$WORKSPACES_DIR" --git && echo "✅ Gas Town workspace initialized"
        fi
        if command -v dolt >/dev/null 2>&1 && [ -d "$WORKSPACES_DIR/.beads" ]; then
            if ! dolt --data-dir="$WORKSPACES_DIR/.beads" sql -q "SELECT 1" >/dev/null 2>&1; then
                echo "Initializing Dolt database..."
                gt dolt init-rig town && echo "✅ Dolt database initialized"
            fi
        fi
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

# Setup Paperclip AI (agent orchestration platform)
# Clones the repo, installs deps, runs migrations, and starts the dev server.
# The company/agents are bootstrapped via the board persona file at load time.
setup_paperclip() {
    echo "Setting up Paperclip AI..."
    paperclip_dir="/tmp/paperclip"

    # Clone if not present
    if [ ! -d "$paperclip_dir" ]; then
        echo "Cloning Paperclip..."
        if git clone https://github.com/paperclipai/paperclip.git "$paperclip_dir"; then
            echo "✅ Paperclip cloned to $paperclip_dir"
        else
            echo "⚠️  Warning: Failed to clone Paperclip"
            return 1
        fi
    else
        echo "✅ Paperclip already present at $paperclip_dir"
    fi

    # Check for pnpm
    if ! command -v pnpm >/dev/null 2>&1; then
        echo "Installing pnpm..."
        npm install -g pnpm || { echo "⚠️  pnpm install failed"; return 1; }
    fi

    # Install dependencies
    echo "Installing Paperclip dependencies..."
    cd "$paperclip_dir" || return 1
    if pnpm install; then
        echo "✅ Paperclip dependencies installed"
    else
        echo "⚠️  Warning: pnpm install failed"
        cd - >/dev/null
        return 1
    fi

    # Configure remote Postgres if PAPERCLIP_DATABASE_URL is set
    paperclip_config_dir="$HOME/.paperclip/instances/default"
    paperclip_config="$paperclip_config_dir/config.json"
    if [ -n "$PAPERCLIP_DATABASE_URL" ] && [ ! -f "$paperclip_config" ]; then
        mkdir -p "$paperclip_config_dir"
        cat > "$paperclip_config" <<CONF
{
  "\$meta": { "version": 1, "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)", "source": "configure" },
  "database": { "mode": "postgres", "connectionString": "$PAPERCLIP_DATABASE_URL" },
  "logging": { "mode": "file" },
  "server": { "deploymentMode": "local_trusted", "host": "127.0.0.1", "port": 3100 }
}
CONF
        echo "✅ Paperclip configured for remote Postgres"
    elif [ -f "$paperclip_config" ]; then
        echo "✅ Paperclip config already exists"
    fi

    # Run DB migrations
    echo "Running Paperclip DB migrations..."
    pnpm db:migrate 2>/dev/null || echo "⚠️  DB migration skipped or failed (may already be up to date)"

    # Start dev server in background if not already running
    if curl -s http://127.0.0.1:3100/api/companies >/dev/null 2>&1; then
        echo "✅ Paperclip server already running on port 3100"
    else
        echo "Starting Paperclip dev server..."
        nohup pnpm dev >/tmp/paperclip-server.log 2>&1 &
        echo "  Waiting for server to come up..."
        for i in 1 2 3 4 5 6 7 8 9 10; do
            if curl -s http://127.0.0.1:3100/api/companies >/dev/null 2>&1; then
                echo "✅ Paperclip dev server started (port 3100)"
                break
            fi
            sleep 2
        done
        if ! curl -s http://127.0.0.1:3100/api/companies >/dev/null 2>&1; then
            echo "⚠️  Server didn't start within 20s. Check /tmp/paperclip-server.log"
        fi
    fi

    cd - >/dev/null

    # Copy board persona file into the Paperclip project and symlink to ~/.claude
    script_dir=$(dirname "$(readlink -f "$0")")
    persona_source="$script_dir/claude/board-persona.md"
    persona_target="$paperclip_dir/.claude/board-persona.md"
    if [ -f "$persona_source" ]; then
        mkdir -p "$paperclip_dir/.claude"
        cp "$persona_source" "$persona_target"
        ln -sf "$persona_target" "$HOME/.claude/paperclip.md"
        echo "✅ Board persona installed (load ~/.claude/paperclip.md persona)"
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
        setup_paperclip
        merge_cursor_work_mcp_entries
    elif [ -t 0 ]; then
        printf "Setup work-specific tools (Glean, Datadog, MongoDB, Netlify, Paperclip)? [y/N] "
        read -r is_work
        if [ "$is_work" = "y" ] || [ "$is_work" = "Y" ]; then
            setup_glean_mcp
            setup_datadog_mcp
            setup_mongodb_mcp
            install_netlify_cli
            setup_netlify_mcp
            setup_paperclip
            merge_cursor_work_mcp_entries
        else
            echo "Skipping work-specific tools."
        fi
    else
        echo "Skipping work-specific tools (non-interactive, WORK_MACHINE not set). Includes: Glean, Datadog, MongoDB, Netlify, Paperclip."
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

# Sync work secrets from Ona into ~/.ona_env without printing values.
sync_ona_env_from_ona() {
    if [ "$WORK_MACHINE" != "1" ]; then
        return 0
    fi

    script_dir=$(dirname "$(readlink -f "$0")")
    sync_script="$script_dir/sync-ona-env-to-cursor-cloud.sh"
    if [ -x "$sync_script" ]; then
        "$sync_script" || true
    fi
}

# Configure GitHub CLI and Git identity from the work Ona GH_TOKEN.
setup_work_github_auth() {
    if [ "$WORK_MACHINE" != "1" ]; then
        return 0
    fi

    script_dir=$(dirname "$(readlink -f "$0")")
    auth_script="$script_dir/scripts/setup_work_github_auth.sh"
    if [ -x "$auth_script" ]; then
        "$auth_script" || true
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

# Install the Statsig CLI (siggy) and lock in the console API key.
# Work machines only. Reads the console key from STATSIG_CONSOLE_API_KEYS.
install_siggy_cli() {
    echo "Checking for Statsig CLI (siggy)..."

    if command -v siggy >/dev/null 2>&1; then
        echo "✅ Statsig CLI already installed"
    else
        install_node_if_missing || return 1
        echo "Installing Statsig CLI with npm..."
        if npm install -g @statsig/siggy; then
            echo "✅ Statsig CLI installed successfully"
        else
            echo "⚠️  Warning: Failed to install Statsig CLI"
            echo "   Try manually: npm install -g @statsig/siggy"
            return 1
        fi
    fi

    if [ -n "${STATSIG_CONSOLE_API_KEYS:-}" ]; then
        echo "Configuring Statsig console API key from STATSIG_CONSOLE_API_KEYS..."
        # Redirect output so the key never lands in logs.
        if siggy config -c "$STATSIG_CONSOLE_API_KEYS" >/dev/null 2>&1; then
            echo "✅ Statsig console API key configured"
        else
            echo "⚠️  Warning: Failed to configure Statsig console API key"
        fi
    else
        echo "⚠️  No STATSIG_CONSOLE_API_KEYS found in environment; skipping siggy auth"
        echo "   Set it and re-run, or configure manually: siggy config -c <console-api-key>"
    fi
}

# Install packages (Linux only)
if [ "$OS" = "linux" ]; then
    install_from_apt "lua5.4"
    install_from_apt "gh"
fi

create_symlinks
setup_cloudev_tasks
setup_ona_default_shell

if [ "$WORK_MACHINE" = "1" ]; then
    sync_ona_env_from_ona
    setup_work_github_auth
fi

# Install tools from URLs
install_from_url "uv" "uv" "https://astral.sh/uv/install.sh"
install_from_url "Claude Code" "claude" "https://claude.ai/install.sh"
install_langsmith_cli
if [ "$WORK_MACHINE" = "1" ]; then
    install_pup_cli
    install_gastown
    install_siggy_cli
    install_from_url "Cortex Code" "cortex" "https://ai.snowflake.com/static/cc-scripts/install.sh"
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
setup_rtk
setup_agent_maturity
setup_superpowers_plugin
setup_vanta_ai_platform_plugin

# Setup work-specific tools (conditional)
setup_work_tools

# Align Cursor MCP with Claude Code user config (after all claude mcp add steps)
sync_cursor_mcp_from_claude || true
