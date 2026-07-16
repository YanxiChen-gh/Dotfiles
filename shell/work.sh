#!/bin/sh
# Work-specific shell configuration
# Sourced when WORK_MACHINE=1 is set
# Add work aliases, paths, and environment variables here

# ------------------- Vanta/Viagogo Aliases ------------------------

# Add work-specific aliases here as needed
# Example:
# alias vpn="sudo openconnect vpn.company.com"

# ------------------- Work PATH Additions ------------------------
# Dotfiles root is already on PATH from ~/.zshrc when DOTFILES_DIR is set.

# ------------------- Work Environment ------------------------
# Cursor Cloud writes work secrets synced from Ona to ~/.ona_env. Source it only
# for work shells and keep local VM identity/path variables intact.
if [ -f "$HOME/.ona_env" ]; then
    _work_saved_HOME=$HOME
    _work_saved_USER=${USER:-}
    _work_saved_LOGNAME=${LOGNAME:-}
    _work_saved_SHELL=${SHELL:-}
    _work_saved_PWD=$PWD
    _work_saved_PATH=$PATH
    # shellcheck disable=SC1091
    . "$HOME/.ona_env"
    export HOME=$_work_saved_HOME
    [ -n "$_work_saved_USER" ] && export USER=$_work_saved_USER
    [ -n "$_work_saved_LOGNAME" ] && export LOGNAME=$_work_saved_LOGNAME
    [ -n "$_work_saved_SHELL" ] && export SHELL=$_work_saved_SHELL
    export PWD=$_work_saved_PWD
    export PATH=$_work_saved_PATH
    unset _work_saved_HOME _work_saved_USER _work_saved_LOGNAME _work_saved_SHELL _work_saved_PWD _work_saved_PATH
fi

# Work-managed binaries take precedence over system tools with the same name.
export PATH="$HOME/.local/bin:$PATH"

if [ -n "${DOTFILES_DIR:-}" ]; then
    alias gws-work-auth="$DOTFILES_DIR/scripts/setup_work_google_workspace_auth.sh"
fi
