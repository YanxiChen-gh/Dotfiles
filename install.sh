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

SCRIPT_DIR=""

# Resolve the directory containing this installer without relying on GNU readlink.
resolve_script_dir() {
    if [ -n "$SCRIPT_DIR" ]; then
        printf '%s\n' "$SCRIPT_DIR"
        return 0
    fi

    script_path=$0
    case "$script_path" in
        */*) ;;
        *)
            resolved=$(command -v -- "$script_path" 2>/dev/null || true)
            if [ -n "$resolved" ]; then
                script_path=$resolved
            fi
            ;;
    esac

    script_dir=$(dirname -- "$script_path")
    SCRIPT_DIR=$(cd -- "$script_dir" 2>/dev/null && pwd -P)
    if [ -z "$SCRIPT_DIR" ]; then
        echo "⚠️  Warning: could not resolve script directory" >&2
        return 1
    fi
    printf '%s\n' "$SCRIPT_DIR"
}


# Load function definitions from install.d/ (order among definitions does not matter; all are defined before the orchestration below runs).
SCRIPT_DIR=$(resolve_script_dir) || exit 1
for _module in "$SCRIPT_DIR"/install.d/*.sh; do
    [ -f "$_module" ] && . "$_module"
done
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

# Install AXI agent skills: Lavish (HTML artifact review) + Chrome DevTools automation
install_axi_skill "kunchenguid/lavish-axi" "lavish"
install_axi_skill "kunchenguid/chrome-devtools-axi" "chrome-devtools-axi"

# Setup Claude Code config and commands
setup_claude_config
setup_advisors
setup_rtk
setup_agent_maturity
setup_superpowers_plugin
setup_vanta_ai_platform_plugin

# Setup work-specific tools (conditional)
setup_work_tools

# Align Cursor MCP with Claude Code user config (after all claude mcp add steps)
sync_cursor_mcp_from_claude || true
