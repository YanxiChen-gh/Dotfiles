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

