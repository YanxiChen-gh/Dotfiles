#!/bin/sh
# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.
#
# oh-my-pi (omp) harness. It runs by default and uses its own ~/.omp config dir,
# so it coexists with OpenCode. Set OMP_EXPERIMENT=0 to skip the integration.

omp_experiment_enabled() {
    [ "${OMP_EXPERIMENT:-1}" != "0" ]
}

omp_ready_marker() {
    printf '%s\n' "${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}/.dotfiles-ready"
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

configure_omp_defaults() {
    omp_binary="${PI_INSTALL_DIR:-$HOME/.local/bin}/omp"
    if [ ! -x "$omp_binary" ]; then
        echo "⚠️  Warning: cannot configure omp defaults; $omp_binary is unavailable"
        return 1
    fi

    omp_default_model="openai-codex/gpt-6-astra"
    omp_api_gpt6_sol_model="openai/gpt-6-sol"
    omp_codex_terra_model="openai-codex/gpt-5.6-terra"
    omp_api_terra_model="openai/gpt-5.6-terra"
    omp_codex_sol_model="openai-codex/gpt-5.6-sol"
    omp_api_sol_model="openai/gpt-5.6-sol"

    (cd "$HOME" && env -u PI_CONFIG_FILES \
        "$omp_binary" config set hideThinkingBlock true >/dev/null) || return 1

    model_roles=$(cd "$HOME" && env -u PI_CONFIG_FILES \
        "$omp_binary" config get modelRoles 2>/dev/null) || {
        echo "⚠️  Warning: could not read omp model roles"
        return 1
    }
    updated_roles=$(printf '%s' "$model_roles" \
        | jq -c --arg default_model "$omp_default_model" '.default = $default_model') || {
        echo "⚠️  Warning: could not update omp model roles"
        return 1
    }
    (cd "$HOME" && env -u PI_CONFIG_FILES \
        "$omp_binary" config set modelRoles "$updated_roles" >/dev/null) || return 1

    enabled_models=$(jq -cn \
        --arg default_model "$omp_default_model" \
        --arg api_gpt6_sol_model "$omp_api_gpt6_sol_model" \
        --arg codex_terra_model "$omp_codex_terra_model" \
        --arg api_terra_model "$omp_api_terra_model" \
        --arg codex_sol_model "$omp_codex_sol_model" \
        --arg api_sol_model "$omp_api_sol_model" \
        '[$default_model, $api_gpt6_sol_model, $codex_terra_model, $api_terra_model, $codex_sol_model, $api_sol_model]') || {
        echo "⚠️  Warning: could not configure the omp model allow-list"
        return 1
    }
    (cd "$HOME" && env -u PI_CONFIG_FILES \
        "$omp_binary" config set enabledModels "$enabled_models" >/dev/null) || return 1

    echo "✅ omp default model set to $omp_default_model"
    echo "   Run /login openai-codex for GPT-6 Astra; set OPENAI_API_KEY for selectable OpenAI API models."
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
    configure_omp_defaults || return 1

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

setup_omp_mcp() {
    if ! command -v python3 >/dev/null 2>&1; then
        if [ "${WORK_MACHINE:-}" = "1" ] && omp_experiment_enabled; then
            echo "Warning: OMP MCP setup requires python3"
            return 1
        fi
        return 0
    fi

    script_dir=$(resolve_script_dir) || return 1
    if [ "${WORK_MACHINE:-}" = "1" ]; then
        omp_experiment_enabled || return 0
        python3 "$script_dir/scripts/ensure_omp_mcp.py" && return 0
    else
        python3 "$script_dir/scripts/ensure_omp_mcp.py" --remove-all-profiles && return 0
    fi
    echo "Warning: OMP MCP setup failed"
    return 1
}

herdr_version_at_least() {
    candidate_version=${1#v}
    minimum_version=${2#v}

    case "$candidate_version" in
        *[!0-9.]*|.*|*.) return 1 ;;
    esac
    case "$minimum_version" in
        *[!0-9.]*|.*|*.) return 1 ;;
    esac

    old_ifs=$IFS
    IFS=.
    set -- $candidate_version
    IFS=$old_ifs
    [ "$#" -eq 3 ] || return 1
    candidate_major=$1
    candidate_minor=$2
    candidate_patch=$3

    IFS=.
    set -- $minimum_version
    IFS=$old_ifs
    [ "$#" -eq 3 ] || return 1
    minimum_major=$1
    minimum_minor=$2
    minimum_patch=$3

    [ -n "$candidate_major" ] && [ -n "$candidate_minor" ] && [ -n "$candidate_patch" ] || return 1
    [ -n "$minimum_major" ] && [ -n "$minimum_minor" ] && [ -n "$minimum_patch" ] || return 1

    [ "$candidate_major" -gt "$minimum_major" ] && return 0
    [ "$candidate_major" -lt "$minimum_major" ] && return 1
    [ "$candidate_minor" -gt "$minimum_minor" ] && return 0
    [ "$candidate_minor" -lt "$minimum_minor" ] && return 1
    [ "$candidate_patch" -ge "$minimum_patch" ]
}

ensure_herdr_omp_nested_session_isolation() {
    required_version=0.9.1
    reported_version=$("$herdr_bin" --version 2>/dev/null) || {
        echo "⚠️  Warning: could not determine the installed Herdr version"
        return 1
    }
    reported_version=${reported_version#herdr }

    herdr_version_at_least "$reported_version" "$required_version" && return 0

    echo "Updating Herdr to $required_version or newer for OMP nested-session isolation..."
    if ! "$herdr_bin" update; then
        echo "⚠️  Warning: Herdr update failed; OMP integration was not installed"
        return 1
    fi

    reported_version=$("$herdr_bin" --version 2>/dev/null) || {
        echo "⚠️  Warning: could not determine the updated Herdr version"
        return 1
    }
    reported_version=${reported_version#herdr }
    if ! herdr_version_at_least "$reported_version" "$required_version"; then
        echo "⚠️  Warning: Herdr $required_version or newer is required for OMP nested-session isolation"
        return 1
    fi
}

install_herdr_omp_integration() {
    omp_experiment_enabled || return 0

    herdr_bin=$(command -v herdr 2>/dev/null || true)
    if [ -z "$herdr_bin" ] && [ -x "$HOME/.local/bin/herdr" ]; then
        herdr_bin="$HOME/.local/bin/herdr"
    fi
    if [ -z "$herdr_bin" ]; then
        echo "⚠️  Herdr is unavailable; omp will not become the Herdr default"
        return 1
    fi
    ensure_herdr_omp_nested_session_isolation || return 1

    if ! "$herdr_bin" integration install omp; then
        echo "⚠️  Warning: Herdr omp integration installation failed"
        echo "   If Pi and omp share an extensions dir, set PI_CODING_AGENT_DIR first."
        return 1
    fi
    echo "✅ Herdr omp integration installed (native lifecycle state + session restore)"
}

validate_omp_maturity() {
    maturity="${AGENT_MATURITY_HOME:-$HOME/agent-maturity}"
    missing=""
    for path in \
        "$maturity/scripts/record-task-outcome.sh" \
        "$maturity/scripts/sync-maturity-data.sh" \
        "$HOME/.agents/skills/record-task-outcome/SKILL.md" \
        "$HOME/.agent-maturity.env"
    do
        [ -e "$path" ] || missing="$missing $path"
    done
    if [ -n "$missing" ]; then
        echo "⚠️  omp agent-maturity integration incomplete; missing:$missing"
        return 1
    fi
}

setup_omp_integration() {
    if ! omp_experiment_enabled; then
        echo "ℹ️  omp integration disabled by OMP_EXPERIMENT=0"
        return 0
    fi

    ready_marker=$(omp_ready_marker)
    if ! rm -f "$ready_marker"; then
        echo "⚠️  Cannot invalidate $ready_marker; Herdr will fall back to OpenCode"
        return 1
    fi
    if ! validate_omp_maturity || ! install_omp || ! setup_omp_config; then
        echo "⚠️  omp integration is incomplete; Herdr will fall back to OpenCode"
        return 1
    fi
    if [ "${WORK_MACHINE:-}" = "1" ] && ! setup_omp_mcp; then
        echo "⚠️  omp integration is incomplete; Herdr will fall back to OpenCode"
        return 1
    fi
    if ! install_herdr_omp_integration; then
        echo "⚠️  omp integration is incomplete; Herdr will fall back to OpenCode"
        return 1
    fi
    if ! mkdir -p "${ready_marker%/*}" || ! : > "$ready_marker"; then
        echo "⚠️  Cannot publish $ready_marker; Herdr will fall back to OpenCode"
        return 1
    fi
    echo "✅ omp integration ready for Herdr"
}
