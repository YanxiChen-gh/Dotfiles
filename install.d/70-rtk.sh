# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

# Install RTK and enable hooks for Claude Code, OpenCode, and Cursor.
# Claude: PreToolUse hook in ~/.claude/settings.json
# Cursor: preToolUse hook in cursor/hooks.json (symlinked to ~/.cursor/hooks.json)
setup_rtk() {
    echo "Setting up RTK (token-optimized shell output)..."

    install_from_url "RTK" "rtk" "https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"

    if ! command -v rtk >/dev/null 2>&1; then
        echo "⚠️  RTK binary not found; skipping agent hook registration"
        return 1
    fi

    # Opt out of telemetry unless explicitly enabled by the user.
    export RTK_TELEMETRY_DISABLED=1

    # Claude Code - automatic bash rewrite via settings.json hook
    if command -v claude >/dev/null 2>&1; then
        if rtk init -g --hook-only --auto-patch 2>/dev/null; then
            echo "✅ RTK hook registered for Claude Code"
        else
            echo "⚠️  RTK Claude Code hook registration failed (run: rtk init -g --hook-only --auto-patch)"
        fi
    else
        echo "ℹ️  Claude Code not installed; skipping RTK Claude hook"
    fi

    # OpenCode - automatic shell rewrite through its plugin API.
    if command -v opencode >/dev/null 2>&1; then
        if rtk init -g --opencode --auto-patch 2>/dev/null; then
            echo "✅ RTK plugin registered for OpenCode"
        else
            echo "⚠️  RTK OpenCode plugin registration failed (run: rtk init -g --opencode --auto-patch)"
        fi
    else
        echo "ℹ️  OpenCode not installed; skipping RTK OpenCode plugin"
    fi

    # Cursor - automatic shell rewrite via hooks.json (versioned in dotfiles)
    if rtk init -g --agent cursor --hook-only --auto-patch 2>/dev/null; then
        echo "✅ RTK hook verified for Cursor"
    elif [ -f "$HOME/.cursor/hooks.json" ]; then
        echo "✅ RTK Cursor hook present (cursor/hooks.json)"
    else
        echo "⚠️  RTK Cursor hook not configured (re-run install or: rtk init -g --agent cursor --hook-only --auto-patch)"
    fi

    echo "✅ RTK setup complete (rtk gain for savings stats)"
}
