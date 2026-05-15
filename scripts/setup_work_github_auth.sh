#!/bin/sh
set -eu

# Configure GitHub CLI and Git identity from the work Ona environment.
# This script never prints token values.

if [ "${WORK_MACHINE:-}" != "1" ]; then
    echo "Skipping GitHub auth setup: WORK_MACHINE is not set to 1."
    exit 0
fi

if [ -f "$HOME/.ona_env" ]; then
    saved_HOME=$HOME
    saved_USER=${USER:-}
    saved_LOGNAME=${LOGNAME:-}
    saved_SHELL=${SHELL:-}
    saved_PWD=$PWD
    saved_PATH=$PATH
    # shellcheck disable=SC1091
    . "$HOME/.ona_env"
    export HOME=$saved_HOME
    [ -n "$saved_USER" ] && export USER=$saved_USER
    [ -n "$saved_LOGNAME" ] && export LOGNAME=$saved_LOGNAME
    [ -n "$saved_SHELL" ] && export SHELL=$saved_SHELL
    export PWD=$saved_PWD
    export PATH=$saved_PATH
fi

if [ -z "${GH_TOKEN:-}" ]; then
    echo "Skipping GitHub auth setup: GH_TOKEN is not present."
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "Skipping GitHub auth setup: gh CLI is not installed."
    exit 0
fi

github_user=${GITHUB_USER:-YanxiChen-gh}
git_name=${GIT_AUTHOR_NAME:-${GIT_COMMITTER_NAME:-Yanxi Chen}}
git_email=${GIT_AUTHOR_EMAIL:-${GIT_COMMITTER_EMAIL:-13044821+${github_user}@users.noreply.github.com}}

token_login=$(GH_TOKEN=$GH_TOKEN gh api user --jq .login 2>/dev/null || true)
if [ -z "$token_login" ]; then
    echo "Skipping GitHub auth setup: GH_TOKEN could not authenticate with GitHub."
    exit 0
fi

if [ "$token_login" != "$github_user" ]; then
    echo "Skipping GitHub auth setup: GH_TOKEN belongs to $token_login, expected $github_user."
    exit 0
fi

env -u GH_TOKEN -u GITHUB_TOKEN gh auth logout --hostname github.com --user cursor >/dev/null 2>&1 || true
if ! printf '%s' "$GH_TOKEN" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --hostname github.com --git-protocol https --with-token >/dev/null 2>&1; then
    if ! env -u GH_TOKEN -u GITHUB_TOKEN gh api user --jq .login >/dev/null 2>&1; then
        echo "GitHub auth setup failed."
        exit 1
    fi
fi

git_config_dir="$HOME/.config/git"
git_config_file="$git_config_dir/config"
mkdir -p "$git_config_dir"

current_git_name=$(git config --file "$git_config_file" --get user.name 2>/dev/null || true)
current_git_email=$(git config --file "$git_config_file" --get user.email 2>/dev/null || true)
current_credential_helper=$(git config --file "$git_config_file" --get credential.helper 2>/dev/null || true)

[ "$current_git_name" = "$git_name" ] || git config --file "$git_config_file" user.name "$git_name"
[ "$current_git_email" = "$git_email" ] || git config --file "$git_config_file" user.email "$git_email"
[ "$current_credential_helper" = "!gh auth git-credential" ] || git config --file "$git_config_file" credential.helper '!gh auth git-credential'

echo "Configured GitHub CLI and Git identity for $github_user."
