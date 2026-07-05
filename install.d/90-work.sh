# shellcheck shell=sh
# Sourced by ../install.sh — function definitions only.

# Setup work-specific tools (Glean MCP, Datadog MCP, MongoDB MCP, etc.)
# Only runs if WORK_MACHINE=1 or user confirms interactively
setup_work_tools() {
    if [ "$WORK_MACHINE" = "1" ]; then
        echo "Work machine detected (WORK_MACHINE=1). Setting up work tools..."
        setup_glean_mcp
        setup_datadog_mcp
        setup_mongodb_mcp
        install_netlify_cli
        setup_netlify_mcp
        merge_cursor_work_mcp_entries
    elif [ -t 0 ]; then
        printf "Setup work-specific tools (Glean, Datadog, MongoDB, Netlify)? [y/N] "
        read -r is_work
        if [ "$is_work" = "y" ] || [ "$is_work" = "Y" ]; then
            setup_glean_mcp
            setup_datadog_mcp
            setup_mongodb_mcp
            install_netlify_cli
            setup_netlify_mcp
            merge_cursor_work_mcp_entries
        else
            echo "Skipping work-specific tools."
        fi
    else
        echo "Skipping work-specific tools (non-interactive, WORK_MACHINE not set). Includes: Glean, Datadog, MongoDB, Netlify."
    fi
}

# Sync work secrets from Ona into ~/.ona_env without printing values.
sync_ona_env_from_ona() {
    if [ "$WORK_MACHINE" != "1" ]; then
        return 0
    fi

    script_dir=$(resolve_script_dir) || return 1
    sync_script="$script_dir/sync-ona-env-to-cursor-cloud.sh"
    if [ -x "$sync_script" ]; then
        "$sync_script" || true
    fi
}

# Configure GitHub CLI and Git identity from the work Ona GH_TOKEN.
setup_work_github_auth() {
    if [ "$WORK_MACHINE" != "1" ]; then
        return 0
    fi

    script_dir=$(resolve_script_dir) || return 1
    auth_script="$script_dir/scripts/setup_work_github_auth.sh"
    if [ -x "$auth_script" ]; then
        "$auth_script" || true
    fi
}

