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

install_omp() {
    omp_experiment_enabled || return 0

    echo "Checking for omp (oh-my-pi)..."
    omp_binary="${PI_INSTALL_DIR:-$HOME/.local/bin}/omp"
    legacy_omp_backup=""
    if [ -L "$omp_binary" ]; then
        omp_source=$(readlink "$omp_binary")
        case "$omp_source" in
            *pi-coding-agent*/dist/cli.js)
                legacy_omp_backup="$omp_binary.pre-standalone-$$"
                if [ -e "$legacy_omp_backup" ] || [ -L "$legacy_omp_backup" ]; then
                    echo "⚠️  Warning: could not safely back up $omp_binary"
                    return 1
                fi
                mv "$omp_binary" "$legacy_omp_backup" || return 1
                ;;
        esac
    fi
    if [ -x "$omp_binary" ] && omp_version_output=$("$omp_binary" --version 2>/dev/null); then
        echo "✅ omp already installed ($omp_version_output)"
        return 0
    fi

    omp_version=${OMP_VERSION:-latest}
    echo "Installing omp ($omp_version) as a standalone binary..."
    install_status=0
    if [ "$omp_version" = "latest" ]; then
        curl -fsSL https://omp.sh/install | sh -s -- --binary || install_status=$?
    else
        case "$omp_version" in
            v*) omp_ref=$omp_version ;;
            *) omp_ref="v$omp_version" ;;
        esac
        curl -fsSL https://omp.sh/install | sh -s -- --binary --ref "$omp_ref" || install_status=$?
    fi

    if [ "$install_status" -ne 0 ] || [ ! -x "$omp_binary" ] || ! omp_version_output=$("$omp_binary" --version 2>/dev/null); then
        if [ -n "$legacy_omp_backup" ]; then
            rm -f "$omp_binary"
            mv "$legacy_omp_backup" "$omp_binary"
        fi
        echo "⚠️  Warning: omp installation failed"
        echo "   Try manually: curl -fsSL https://omp.sh/install | sh -s -- --binary"
        return 1
    fi
    if [ -n "$legacy_omp_backup" ]; then rm -f "$legacy_omp_backup"; fi
    echo "✅ omp installed ($omp_version_output)"
}

remove_legacy_omp_link() {
    target_file=$1
    old_source=$2
    if [ -L "$target_file" ] && [ "$(readlink "$target_file")" = "$old_source" ]; then
        rm -f "$target_file"
        backup_file="$target_file.pre-dotfiles"
        if [ -e "$backup_file" ] || [ -L "$backup_file" ]; then
            mv "$backup_file" "$target_file"
            echo "ℹ️  Restored existing omp state from $backup_file"
        fi
    fi
}

setup_omp_config() {
    omp_experiment_enabled || return 0

    script_dir=$(resolve_script_dir) || return 1
    source_dir="$script_dir/omp"
    agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
    ext_dir="$agent_dir/extensions"

    mkdir -p "$ext_dir"
    # omp owns credentials, model selection, and setup state. Older revisions
    # linked these mutable files into Dotfiles; remove only those exact links.
    remove_legacy_omp_link "$agent_dir/models.yml" "$source_dir/agent/models.yml"
    remove_legacy_omp_link "$agent_dir/config.yml" "$source_dir/agent/config.yml"
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

    echo "✅ omp harness extension and global rules linked ($agent_dir)"
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
