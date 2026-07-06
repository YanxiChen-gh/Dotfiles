# shellcheck shell=sh
# Sourced by ../install.sh — function definitions only.

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

# Install the Neovim binary if missing. create_symlinks/setup_nvim_config only
# link config — without this a fresh CDE has the config but no `nvim` to run it.
# Uses the official static build (distro apt lags); Homebrew on macOS.
install_neovim() {
    if command -v nvim >/dev/null 2>&1; then
        echo "✅ Neovim already installed ($(nvim --version | head -1))"
        return 0
    fi

    if [ "$OS" = "macos" ]; then
        if command -v brew >/dev/null 2>&1; then
            brew install neovim && echo "✅ Neovim installed" || echo "⚠️  Warning: brew install neovim failed"
        else
            echo "⚠️  Neovim missing and Homebrew unavailable; install manually: brew install neovim"
        fi
        return 0
    fi

    if [ "$OS" != "linux" ]; then
        echo "⚠️  Neovim auto-install unsupported on OS '$OS'; install manually"
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

# Setup Neovim/Vim config.
# .vimrc at the repo root is already linked to ~/.vimrc by create_symlinks. Neovim
# reads ~/.config/nvim/init.vim instead, so link our init.vim (which sources ~/.vimrc)
# there, and link coc-settings.json into both ~/.config/nvim (nvim) and ~/.vim (vim).
setup_nvim_config() {
    script_dir=$(resolve_script_dir) || return 1

    nvim_dir="$HOME/.config/nvim"
    mkdir -p "$nvim_dir" "$HOME/.vim"

    for pair in \
        "$script_dir/nvim/init.vim:$nvim_dir/init.vim" \
        "$script_dir/nvim/coc-settings.json:$nvim_dir/coc-settings.json" \
        "$script_dir/nvim/coc-settings.json:$HOME/.vim/coc-settings.json"; do
        src=${pair%%:*}
        dest=${pair#*:}
        [ -f "$src" ] || continue
        rm -f "$dest"
        ln -s "$src" "$dest"
    done
    echo "✅ Linked Neovim/Vim config (init.vim, coc-settings.json)"
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

