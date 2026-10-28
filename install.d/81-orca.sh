# shellcheck shell=sh
# Sourced by ../install.sh - function definitions only.

install_orca() (
    set -e
    mkdir -p "$HOME/.local/bin" || return 1
    orca_cli=
    for candidate in "$(command -v orca 2>/dev/null || true)" \
        "$HOME/.orca/cli/bin/orca" "$(command -v orca-ide 2>/dev/null || true)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ] && \
                "$candidate" skills list >/dev/null 2>&1; then
            orca_cli=$candidate
            break
        fi
    done

    if [ -z "$orca_cli" ]; then
        if [ "$OS" != linux ]; then
            echo "Install Orca and register its CLI in Settings > General > Orca CLI, then rerun install.sh." >&2
            return 1
        fi
        case "$(uname -m)" in
            x86_64) orca_asset=orca-linux.AppImage ;;
            aarch64|arm64) orca_asset=orca-linux-arm64.AppImage ;;
            *) echo "Unsupported Orca architecture: $(uname -m)" >&2; return 1 ;;
        esac
        orca_root="$HOME/.local/share/orca"
        orca_cli="$orca_root/squashfs-root/resources/bin/orca-ide"
        if [ ! -x "$orca_cli" ]; then
            if [ -e "$orca_root" ] || [ -L "$orca_root" ]; then
                echo "Refusing to overwrite existing Orca installation: $orca_root" >&2
                return 1
            fi
            mkdir -p "$HOME/.local/share" || return 1
            orca_stage=$(mktemp -d "$HOME/.local/share/.orca-install.XXXXXX") || return 1
            trap 'rm -rf "$orca_stage"' EXIT
            curl -fSL --retry 3 "https://github.com/stablyai/orca/releases/latest/download/$orca_asset" \
                -o "$orca_stage/orca.AppImage" || return 1
            chmod +x "$orca_stage/orca.AppImage" || return 1
            (cd "$orca_stage" && ./orca.AppImage --appimage-extract >/dev/null) || return 1
            "$orca_stage/squashfs-root/resources/bin/orca-ide" skills list >/dev/null || return 1
            rm "$orca_stage/orca.AppImage" || return 1
            mv "$orca_stage" "$orca_root" || return 1
        fi
    fi

    "$orca_cli" skills list >/dev/null || return 1
    if [ "$orca_cli" != "$HOME/.local/bin/orca" ]; then
        if [ -e "$HOME/.local/bin/orca" ] || [ -L "$HOME/.local/bin/orca" ]; then
            if [ ! -L "$HOME/.local/bin/orca" ] || \
                    [ "$(readlink "$HOME/.local/bin/orca")" != "$orca_cli" ]; then
                echo "Refusing to overwrite unmanaged command: $HOME/.local/bin/orca" >&2
                return 1
            fi
        else
            ln -s "$orca_cli" "$HOME/.local/bin/orca" || return 1
        fi
    fi
    "$orca_cli" --version || return 1
    "$orca_cli" skills install --skill orca-cli --skill orchestration \
        --skill orca-per-workspace-env --agent claude,codex,cursor,opencode,omp
)
