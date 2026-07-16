# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

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

# Install the Google Workspace CLI at the version tested by these Dotfiles.
# Work machines only; authentication remains an explicit user action.
install_google_workspace_cli() {
    if [ "${WORK_MACHINE:-}" != "1" ]; then
        return 0
    fi

    gws_version="0.22.5"
    install_node_if_missing || return 1

    npm_prefix=$(npm prefix -g 2>/dev/null || true)
    if [ -z "$npm_prefix" ]; then
        echo "⚠️  Could not determine the global npm prefix"
        return 1
    fi
    npm_gws="$npm_prefix/bin/gws"

    installed_version=""
    if [ -x "$npm_gws" ]; then
        installed_version=$("$npm_gws" --version 2>/dev/null | (
            IFS=' ' read -r command version _
            if [ "$command" = "gws" ]; then
                printf '%s\n' "$version"
            fi
        ))
    fi

    if [ "$installed_version" != "$gws_version" ]; then
        if [ -n "$installed_version" ]; then
            echo "Updating Google Workspace CLI from $installed_version to $gws_version..."
        else
            echo "Installing Google Workspace CLI $gws_version..."
        fi

        if ! npm install -g "@googleworkspace/cli@$gws_version"; then
            echo "⚠️  Warning: Failed to install Google Workspace CLI"
            echo "   Try manually: npm install -g @googleworkspace/cli@$gws_version"
            return 1
        fi
    fi

    installed_version=$("$npm_gws" --version 2>/dev/null | (
        IFS=' ' read -r command version _
        if [ "$command" = "gws" ]; then
            printf '%s\n' "$version"
        fi
    ))
    if [ "$installed_version" != "$gws_version" ]; then
        echo "⚠️  Google Workspace CLI installed, but expected $gws_version and found ${installed_version:-unknown}"
        return 1
    fi

    managed_gws_dir="$HOME/.local/bin"
    managed_gws="$managed_gws_dir/gws"
    mkdir -p "$managed_gws_dir"
    if [ -e "$managed_gws" ] && [ ! -L "$managed_gws" ]; then
        echo "⚠️  Refusing to replace unmanaged file at $managed_gws"
        return 1
    fi
    if [ -L "$managed_gws" ]; then
        rm -f "$managed_gws"
    fi
    ln -s "$npm_gws" "$managed_gws"

    echo "✅ Google Workspace CLI $gws_version installed at $managed_gws"
    echo "   Run gws-work-auth to authenticate Docs, Sheets, Slides, and Drive."
}

# Install an AXI agent skill (github.com/kunchenguid/*) for Claude Code and Cursor.
# Install an agent skill for Claude Code and/or Cursor from a GitHub repo.
# Usage: install_agent_skill <github_repo> <skill_name>
install_agent_skill() {
    local repo="$1"
    local skill="$2"
    if command -v claude >/dev/null 2>&1; then
        echo "Installing ${skill} skill for Claude Code..."
        npx skills add "$repo" --agent claude-code --skill "$skill" --yes --global 2>/dev/null \
            && echo "✅ ${skill} skill installed (Claude Code)" \
            || echo "⚠️  ${skill} skill installation failed for Claude Code (can retry manually)"
    fi
    if command -v cursor >/dev/null 2>&1 || [ -d "/Applications/Cursor.app" ] || [ -d "$HOME/.cursor" ]; then
        echo "Installing ${skill} skill for Cursor..."
        npx skills add "$repo" --agent cursor --skill "$skill" --yes --global 2>/dev/null \
            && echo "✅ ${skill} skill installed (Cursor)" \
            || echo "⚠️  ${skill} skill installation failed for Cursor (can retry manually)"
    fi
}
