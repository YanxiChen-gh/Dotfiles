#!/bin/sh

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

# Install a tool from a URL if not already present
# Usage: install_from_url <display_name> <command_name> <install_url>
install_from_url() {
    display_name=$1
    command_name=$2
    install_url=$3

    echo "Checking for $display_name..."
    if command -v "$command_name" >/dev/null 2>&1; then
        echo "✅ $display_name already installed"
    else
        echo "Installing $display_name..."
        if curl -fsSL "$install_url" | sh; then
            echo "✅ $display_name installed successfully"
        else
            echo "⚠️  Warning: $display_name installation failed"
            echo "   You can try to install manually: curl -fsSL $install_url | sh"
        fi
    fi
}

# Create symlinks to dot files
create_symlinks() {
    # Get the directory in which this script lives.
    script_dir=$(dirname "$(readlink -f "$0")")

    # Get a list of all files in this directory that start with a dot.
    files=$(find -maxdepth 1 -type f -name ".*")

    # Create a symbolic link to each file in the home directory.
    for file in $files; do
        name=$(basename $file)
        echo "Creating symlink to $name in home directory."
        rm -rf ~/$name
        ln -s $script_dir/$name ~/$name
    done
}

# Install packages
install_from_apt "lua5.4"

create_symlinks

# Install tools from URLs
install_from_url "uv" "uv" "https://astral.sh/uv/install.sh"
install_from_url "Claude Code" "claude-code" "https://raw.githubusercontent.com/anthropics/claude-code/main/install.sh"

# Setup MCP servers
setup_langsmith_mcp
