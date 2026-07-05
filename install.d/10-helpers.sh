# shellcheck shell=sh
# Sourced by ../install.sh — function definitions only.

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

