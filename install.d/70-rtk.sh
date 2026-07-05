# shellcheck shell=sh
# Sourced by ../install.sh — function definitions only.

# Install RTK and enable for Claude Code, OpenAI Codex (GPT), and Cursor.
# Claude: PreToolUse hook in ~/.claude/settings.json
# Cursor: preToolUse hook in cursor/hooks.json (symlinked to ~/.cursor/hooks.json)
# Codex: AGENTS.md + RTK.md symlinks (~/.codex/); agents prefix shell commands with rtk
setup_rtk() {
    echo "Setting up RTK (token-optimized shell output)..."

    install_from_url "RTK" "rtk" "https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"

    if ! command -v rtk >/dev/null 2>&1; then
        echo "⚠️  RTK binary not found; skipping agent hook registration"
        return 1
    fi

    # Opt out of telemetry unless explicitly enabled by the user.
    export RTK_TELEMETRY_DISABLED=1

    # Claude Code — automatic bash rewrite via settings.json hook
    if command -v claude >/dev/null 2>&1; then
        if rtk init -g --hook-only --auto-patch 2>/dev/null; then
            echo "✅ RTK hook registered for Claude Code"
        else
            echo "⚠️  RTK Claude Code hook registration failed (run: rtk init -g --hook-only --auto-patch)"
        fi
    else
        echo "ℹ️  Claude Code not installed; skipping RTK Claude hook"
    fi

    # Cursor — automatic shell rewrite via hooks.json (versioned in dotfiles)
    if rtk init -g --agent cursor --hook-only --auto-patch 2>/dev/null; then
        echo "✅ RTK hook verified for Cursor"
    elif [ -f "$HOME/.cursor/hooks.json" ]; then
        echo "✅ RTK Cursor hook present (cursor/hooks.json)"
    else
        echo "⚠️  RTK Cursor hook not configured (re-run install or: rtk init -g --agent cursor --hook-only --auto-patch)"
    fi

    # OpenAI Codex (GPT) — AGENTS.md + RTK.md (instruction-based; no bash hook API)
    setup_codex_config
    if [ -f "$HOME/.codex/AGENTS.md" ] && [ -f "$HOME/.codex/RTK.md" ]; then
        echo "✅ RTK instructions linked for OpenAI Codex (GPT)"
    else
        echo "⚠️  Codex RTK config incomplete (expected ~/.codex/AGENTS.md and RTK.md)"
    fi

    echo "✅ RTK setup complete (rtk gain for savings stats)"
}

