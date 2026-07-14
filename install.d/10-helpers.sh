# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

# Link a versioned Dotfiles file without overwriting unmanaged user configuration.
link_dotfiles_file() {
    source_file=$1
    target_file=$2
    shift 2

    if [ -L "$target_file" ] && [ "$(readlink "$target_file")" = "$source_file" ]; then
        return 0
    fi

    if [ -L "$target_file" ]; then
        current_source=$(readlink "$target_file")
        for managed_source in "$@"; do
            if [ "$current_source" = "$managed_source" ]; then
                rm -f "$target_file"
                break
            fi
        done
    fi

    if [ -e "$target_file" ] || [ -L "$target_file" ]; then
        backup_file="$target_file.pre-dotfiles"
        if [ -e "$backup_file" ] || [ -L "$backup_file" ]; then
            echo "⚠️  Preserving unmanaged file because its backup already exists: $target_file"
            return 1
        fi
        mv "$target_file" "$backup_file"
        echo "ℹ️  Preserved existing file at $backup_file"
    fi

    ln -s "$source_file" "$target_file"
}

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

# Ensure Node.js 20+ and npm are available.
install_node_if_missing() {
    node_major=0
    if command -v node >/dev/null 2>&1; then
        node_major=$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)
    fi
    if command -v npm >/dev/null 2>&1 && [ "$node_major" -ge 20 ]; then
        echo "✅ Node.js $(node --version) and npm $(npm --version) already installed"
        return 0
    fi

    if [ "$OS" = "macos" ] && command -v brew >/dev/null 2>&1; then
        echo "Installing Node.js via Homebrew..."
        brew install node
    elif [ "$OS" = "linux" ]; then
        echo "Installing Node.js via NodeSource..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && \
            sudo apt-get install -y nodejs
    else
        echo "⚠️  Node.js 20+ is required; install it from https://nodejs.org/en/download"
    fi

    node_major=0
    if command -v node >/dev/null 2>&1; then
        node_major=$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)
    fi
    if ! command -v npm >/dev/null 2>&1 || [ "$node_major" -lt 20 ]; then
        echo "⚠️  Warning: Node.js 20+ installation failed"
        return 1
    fi
    echo "✅ Node.js installed: $(node --version), npm $(npm --version)"
}

install_python_if_missing() {
    if command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    if [ "$OS" = "macos" ] && command -v brew >/dev/null 2>&1; then
        brew install python
    elif [ "$OS" = "linux" ]; then
        install_from_apt "python3"
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "⚠️  Python3 is required for agent config sync; install it and rerun install.sh"
        return 1
    fi
}
