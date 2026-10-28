# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

# Create symlinks to dot files
create_symlinks() {
    script_dir=$(resolve_script_dir) || return 1

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

# Install Neovim 0.11.3+ when missing or outdated. create_symlinks/setup_nvim_config
# only link config - without this a fresh CDE has the config but no `nvim` to run it.
# Uses the official static build (distro apt lags); Homebrew on macOS.
install_neovim() {
    if command -v nvim >/dev/null 2>&1 && \
       nvim --headless -u NONE -i NONE -c 'if !has("nvim-0.11.3") | cquit 1 | endif' -c 'qa!' >/dev/null 2>&1; then
        echo "✅ Neovim already installed ($(nvim --version | head -1))"
        return 0
    fi

    if command -v nvim >/dev/null 2>&1; then
        echo "Upgrading Neovim to 0.11.3+..."
    fi

    if [ "$OS" = "macos" ]; then
        if command -v brew >/dev/null 2>&1; then
            if brew list neovim >/dev/null 2>&1; then
                brew upgrade neovim && echo "✅ Neovim upgraded" || echo "⚠️  Warning: brew upgrade neovim failed"
            else
                brew install neovim && echo "✅ Neovim installed" || echo "⚠️  Warning: brew install neovim failed"
            fi
        else
            echo "⚠️  Neovim 0.11.3+ missing and Homebrew unavailable; install manually: brew install neovim"
        fi
        return 0
    fi

    if [ "$OS" != "linux" ]; then
        echo "⚠️  Neovim 0.11.3+ auto-install unsupported on OS '$OS'; install manually"
        return 0
    fi

    case "$(uname -m)" in
        x86_64)        release="nvim-linux-x86_64" ;;
        aarch64|arm64) release="nvim-linux-arm64" ;;
        *) echo "⚠️  Unsupported arch for Neovim auto-install: $(uname -m)"; return 0 ;;
    esac

    url="https://github.com/neovim/neovim/releases/download/stable/${release}.tar.gz"
    mkdir -p "$HOME/.local/bin"
    if curl -fsSL "$url" | tar -xz -C "$HOME/.local"; then
        ln -sf "$HOME/.local/$release/bin/nvim" "$HOME/.local/bin/nvim"
        echo "✅ Neovim installed ($("$HOME/.local/bin/nvim" --version | head -1))"
    else
        echo "⚠️  Warning: Neovim installation failed"
        echo "   Try manually: curl -fsSL $url | tar -xz -C \$HOME/.local"
    fi
}

install_typescript_language_service() {
    typescript_version="6.0.3"
    install_dir="$HOME/.local/share/typescript-language-service"
    package_json="$install_dir/node_modules/typescript/package.json"
    if [ -f "$package_json" ] && \
       [ "$(node -p "require('$package_json').version" 2>/dev/null)" = "$typescript_version" ]; then
        echo "✅ TypeScript language service already installed ($typescript_version)"
        return 0
    fi

    echo "Installing TypeScript language service..."
    if npm install --prefix "$install_dir" --no-save "typescript@$typescript_version"; then
        echo "✅ TypeScript language service installed ($typescript_version)"
    else
        echo "⚠️  Warning: TypeScript language service installation failed"
        return 1
    fi
}

# Setup Neovim/Vim config.
# .vimrc at the repo root is already linked to ~/.vimrc by create_symlinks. Neovim
# reads ~/.config/nvim/init.vim instead, so link our init.vim (which sources ~/.vimrc)
# there, then link Neovim's native LSP config.
setup_nvim_config() {
    script_dir=$(resolve_script_dir) || return 1

    nvim_dir="$HOME/.config/nvim"
    mkdir -p "$nvim_dir" "$HOME/.vim"

    for pair in \
        "$script_dir/nvim/init.vim:$nvim_dir/init.vim" \
        "$script_dir/nvim/lsp.lua:$nvim_dir/lsp.lua"; do
        src=${pair%%:*}
        dest=${pair#*:}
        [ -f "$src" ] || continue
        rm -f "$dest"
        ln -s "$src" "$dest"
    done
    for obsolete_coc_config in "$nvim_dir/coc-settings.json" "$HOME/.vim/coc-settings.json"; do
        [ -L "$obsolete_coc_config" ] && rm -f "$obsolete_coc_config"
    done
    echo "✅ Linked Neovim config (init.vim, lsp.lua)"
}

# Setup Claude Dev tasks configuration
# Symlinks cloudev/tasks.json to ~/.cloudev/tasks.json
setup_cloudev_tasks() {
    script_dir=$(resolve_script_dir) || return 1
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

# Symlink herdr's config (leader key) into ~/.config/herdr/config.toml.
setup_herdr_config() {
    script_dir=$(resolve_script_dir) || return 1
    source_config="$script_dir/herdr/config.toml"
    target_dir="$HOME/.config/herdr"
    target_config="$target_dir/config.toml"

    if [ ! -f "$source_config" ]; then
        echo "ℹ️  herdr/config.toml not found, skipping herdr config setup."
        return 0
    fi

    mkdir -p "$target_dir"
    rm -f "$target_config"
    ln -s "$source_config" "$target_config"
    link_dotfiles_file "$script_dir/herdr" "$target_dir/launchers" || return 1
    echo "✅ Linked herdr config: $target_config -> $source_config"

    skill_source="$script_dir/shared-skills/troubleshoot-herdr"
    for skills_dir in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.cursor/skills-cursor"; do
        mkdir -p "$skills_dir" || return 1
        link_dotfiles_file "$skill_source" "$skills_dir/troubleshoot-herdr" || return 1
    done
}

# Symlink treehouse's config (worktree provisioning hook) into
# ~/.config/treehouse/config.toml.
setup_treehouse_config() {
    script_dir=$(resolve_script_dir) || return 1
    source_config="$script_dir/treehouse/config.toml"
    target_dir="$HOME/.config/treehouse"
    target_config="$target_dir/config.toml"

    if [ ! -f "$source_config" ]; then
        echo "ℹ️  treehouse/config.toml not found, skipping treehouse config setup."
        return 0
    fi

    mkdir -p "$target_dir"
    rm -f "$target_config"
    ln -s "$source_config" "$target_config"
    echo "✅ Linked treehouse config: $target_config -> $source_config"
}

# Symlink the WezTerm config into ~/.config/wezterm/wezterm.lua.
setup_wezterm_config() {
    script_dir=$(resolve_script_dir) || return 1
    source_config="$script_dir/wezterm/wezterm.lua"
    target_dir="$HOME/.config/wezterm"
    target_config="$target_dir/wezterm.lua"

    if [ ! -f "$source_config" ]; then
        echo "ℹ️  wezterm/wezterm.lua not found, skipping WezTerm config setup."
        return 0
    fi

    mkdir -p "$target_dir"
    rm -f "$target_config"
    ln -s "$source_config" "$target_config"
    echo "✅ Linked WezTerm config: $target_config -> $source_config"
}

# Set the Ona account's login shell without replacing shells running commands.
setup_ona_default_shell() {
    bashrc="$HOME/.bashrc"
    marker="# >>> dotfiles: default to zsh on Ona >>>"
    if [ -f "$bashrc" ] && grep -qF "$marker" "$bashrc"; then
        bashrc_tmp=$(mktemp) || return 1
        if ! awk '
            $0 == "# >>> dotfiles: default to zsh on Ona >>>" { skip = 1; next }
            $0 == "# <<< dotfiles: default to zsh on Ona <<<" { skip = 0; next }
            !skip { print }
            END { if (skip) exit 1 }
        ' "$bashrc" > "$bashrc_tmp" || ! cat "$bashrc_tmp" > "$bashrc"; then
            rm -f "$bashrc_tmp"
            return 1
        fi
        rm -f "$bashrc_tmp"
        echo "✅ Removed the automatic Bash-to-Zsh switch from $bashrc"
    fi

    [ -n "${IS_ON_ONA:-}" ] || return 0
    if ! command -v zsh >/dev/null 2>&1 && [ "$OS" = "linux" ]; then
        install_from_apt "zsh"
    fi
    zsh_path=$(command -v zsh 2>/dev/null) || return 1
    shell_user=$(id -un) || return 1
    shell_account=$(getent passwd "$shell_user") || return 1
    [ "${shell_account##*:}" != "$zsh_path" ] || return 0
    if sudo -n chsh "$shell_user" --shell "$zsh_path" </dev/null; then
        echo "✅ Login shell set to $zsh_path"
    else
        echo "Could not set the Ona login shell to $zsh_path." >&2
        return 1
    fi
}
