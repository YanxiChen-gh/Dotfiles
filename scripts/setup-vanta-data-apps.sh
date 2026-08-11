#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=${DATA_APPS_DIR:-/workspaces/data-apps}
SNOWFLAKE_USER=${SNOWFLAKE_USER:-}
PYTHON_BIN=${DATA_APPS_PYTHON:-python3}
CONFIG_PYTHON=${SNOWFLAKE_CONFIG_PYTHON:-python3}
GH_BIN=${DATA_APPS_GH:-gh}
CONFIGURE_SNOWFLAKE=${CONFIGURE_VANTA_SNOWFLAKE:-$SCRIPT_DIR/configure_vanta_snowflake.py}

usage() {
    cat <<'EOF'
Usage: setup-vanta-data-apps.sh [--repo-dir DIR] [--user EMAIL]

Clone and provision VantaInc/data-apps, then configure its no-secret local
Snowflake connection. This may install python3-venv when the host lacks it.
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --repo-dir)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            REPO_DIR=$2
            shift 2
            ;;
        --user)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            SNOWFLAKE_USER=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for command in "$PYTHON_BIN" "$CONFIG_PYTHON" "$GH_BIN" git; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command is unavailable: $command" >&2
        exit 1
    fi
done
if [[ ! -f "$CONFIGURE_SNOWFLAKE" ]]; then
    echo "Snowflake configuration helper is missing: $CONFIGURE_SNOWFLAKE" >&2
    exit 1
fi
if ! "$CONFIG_PYTHON" -c 'import sys; raise SystemExit(sys.version_info < (3, 11))'; then
    echo "Python 3.11 or newer is required to manage Snowflake TOML safely." >&2
    exit 1
fi

if [[ -z "$SNOWFLAKE_USER" ]]; then
    SNOWFLAKE_USER=$(git config --global user.email || true)
fi
if [[ ! "$SNOWFLAKE_USER" =~ ^[^@[:space:]]+@vanta\.com$ ]]; then
    echo "Pass --user with your @vanta.com email address." >&2
    exit 1
fi

if [[ -e "$REPO_DIR" ]]; then
    if ! git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        echo "Existing path is not a Git checkout: $REPO_DIR" >&2
        exit 1
    fi
    origin=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)
    case "$origin" in
        git@github.com:VantaInc/data-apps.git|https://github.com/VantaInc/data-apps|https://github.com/VantaInc/data-apps.git) ;;
        *)
            echo "Existing checkout has an unexpected origin: $REPO_DIR" >&2
            exit 1
            ;;
    esac
else
    parent_dir=$(dirname "$REPO_DIR")
    mkdir -p "$parent_dir"
    "$GH_BIN" repo clone VantaInc/data-apps "$REPO_DIR"
fi

if [[ ! -f "$REPO_DIR/requirements.txt" ]]; then
    echo "data-apps requirements.txt is missing from $REPO_DIR" >&2
    exit 1
fi

venv_dir="$REPO_DIR/venv"
if [[ ! -x "$venv_dir/bin/python" ]]; then
    if ! "$PYTHON_BIN" -m venv "$venv_dir"; then
        if ! command -v apt-get >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
            echo "Python venv support is missing. Install python3-venv, then retry." >&2
            exit 1
        fi
        sudo -n apt-get update
        sudo -n apt-get install -y python3-venv
        "$PYTHON_BIN" -m venv --clear "$venv_dir"
    fi
fi
if [[ ! -x "$venv_dir/bin/pip" ]]; then
    echo "Virtual environment did not provide pip: $venv_dir" >&2
    exit 1
fi

PIP_DISABLE_PIP_VERSION_CHECK=1 "$venv_dir/bin/pip" install -r "$REPO_DIR/requirements.txt"
"$CONFIG_PYTHON" "$CONFIGURE_SNOWFLAKE" --user "$SNOWFLAKE_USER"

cat <<EOF
Vanta data-apps is ready at $REPO_DIR.
Authenticate Snowflake with:
  $SCRIPT_DIR/auth-vanta-data-apps-snowflake.sh --repo-dir "$REPO_DIR"
EOF
