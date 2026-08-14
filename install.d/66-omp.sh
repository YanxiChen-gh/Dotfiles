#!/bin/sh
# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.
#
# Experimental oh-my-pi (omp) harness. Everything here is gated behind
# OMP_EXPERIMENT=1 so it never runs during a normal install and never disturbs
# the live opencode setup. omp uses its own ~/.omp config dir, so the two coexist.

omp_experiment_enabled() {
    [ "${OMP_EXPERIMENT:-}" = "1" ]
}

ensure_bun() {
    # omp is a Bun program (its launcher is `#!/usr/bin/env bun`), so Bun must be
    # on PATH for `omp` to run at all - the npm package alone is not enough.
    if command -v bun >/dev/null 2>&1; then
        echo "✅ bun already installed ($(bun --version 2>/dev/null || echo unknown))"
        return 0
    fi
    echo "Installing bun (omp runtime)..."
    if curl -fsSL https://bun.sh/install | bash; then
        export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
        export PATH="$BUN_INSTALL/bin:$PATH"
        echo "✅ bun installed"
    else
        echo "⚠️  bun installation failed; omp cannot run without it"
        echo "   Install manually: curl -fsSL https://bun.sh/install | bash"
        return 1
    fi
}

install_omp() {
    omp_experiment_enabled || return 0

    ensure_bun || return 1

    echo "Checking for omp (oh-my-pi)..."
    if command -v omp >/dev/null 2>&1; then
        echo "✅ omp already installed ($(omp --version 2>/dev/null || echo unknown))"
        return 0
    fi

    # Pin a release rather than tracking latest: omp ships on a ~18h cadence, so an
    # unpinned install is a moving target. Override with OMP_VERSION.
    omp_version=${OMP_VERSION:-latest}
    echo "Installing omp ($omp_version) via npm..."
    if npm install -g "@oh-my-pi/pi-coding-agent@$omp_version"; then
        echo "✅ omp installed"
    else
        echo "⚠️  Warning: omp installation failed"
        echo "   Try manually: npm install -g @oh-my-pi/pi-coding-agent@$omp_version"
        echo "   or: curl -fsSL https://omp.sh/install | sh"
        return 1
    fi
}

setup_omp_config() {
    omp_experiment_enabled || return 0

    script_dir=$(resolve_script_dir) || return 1
    source_dir="$script_dir/omp"
    agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
    ext_dir="$agent_dir/extensions"

    mkdir -p "$ext_dir"
    link_dotfiles_file "$source_dir/agent/models.yml" "$agent_dir/models.yml" || return 1
    link_dotfiles_file "$source_dir/agent/config.yml" "$agent_dir/config.yml" || return 1
    link_dotfiles_file \
        "$source_dir/agent/extensions/dotfiles-harness.ts" \
        "$ext_dir/dotfiles-harness.ts" || return 1
    if [ -f "$source_dir/agent/mcp.json" ]; then
        link_dotfiles_file "$source_dir/agent/mcp.json" "$agent_dir/mcp.json" || return 1
    fi

    # Global rules: reuse the same generated aggregate opencode uses. omp appends
    # APPEND_SYSTEM.md to the system prompt.
    omp_rules="$source_dir/../opencode/AGENTS.md"
    if [ "${WORK_MACHINE:-}" = "1" ]; then
        omp_rules="$source_dir/../opencode/AGENTS-work.md"
    fi
    link_dotfiles_file \
        "$omp_rules" \
        "$agent_dir/APPEND_SYSTEM.md" \
        "$source_dir/../opencode/AGENTS.md" \
        "$source_dir/../opencode/AGENTS-work.md" || return 1

    echo "✅ omp config, harness extension, and global rules linked ($agent_dir)"
}

setup_omp_rtk() {
    omp_experiment_enabled || return 0
    command -v omp >/dev/null 2>&1 || return 0
    command -v rtk >/dev/null 2>&1 || return 0

    # Match the opencode RTK plugin. omp integration may not exist yet; fail soft.
    if rtk init -g --agent omp --auto-patch 2>/dev/null; then
        echo "✅ RTK registered for omp (token-optimized shell output)"
    else
        echo "ℹ️  RTK has no omp integration yet; omp shell output is not token-optimized"
    fi
}

sync_omp_mcp() {
    omp_experiment_enabled || return 0
    command -v python3 >/dev/null 2>&1 || return 0

    script_dir=$(resolve_script_dir) || return 1
    if python3 "$script_dir/scripts/sync_omp_mcp_from_claude.py"; then
        return 0
    fi
    echo "⚠️  omp MCP sync from Claude Code failed"
    return 1
}

install_herdr_omp_integration() {
    omp_experiment_enabled || return 0

    herdr_bin=$(command -v herdr 2>/dev/null || true)
    if [ -z "$herdr_bin" ] && [ -x "$HOME/.local/bin/herdr" ]; then
        herdr_bin="$HOME/.local/bin/herdr"
    fi
    if [ -z "$herdr_bin" ]; then
        echo "⚠️  Herdr is unavailable; skipping its omp integration"
        return 0
    fi

    if ! "$herdr_bin" integration install omp; then
        echo "⚠️  Warning: Herdr omp integration installation failed"
        echo "   If Pi and omp share an extensions dir, set PI_CODING_AGENT_DIR first."
        return 1
    fi
    echo "✅ Herdr omp integration installed (native lifecycle state + session restore)"
}
