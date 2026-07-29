#!/usr/bin/env bash
# Run a Lavish CLI command with host-safe startup settings for the current environment.

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
    SOURCE_DIR=$(cd "$(dirname "$SOURCE")" && pwd)
    SOURCE=$(readlink "$SOURCE")
    [[ "$SOURCE" == /* ]] || SOURCE="$SOURCE_DIR/$SOURCE"
done
SCRIPT_DIR=$(cd "$(dirname "$SOURCE")" && pwd)
PREPARE_SCRIPT="${OPEN_LAVISH_PREPARE_SCRIPT:-$SCRIPT_DIR/prepare-ona-tailnet.sh}"

if [[ "${IS_ON_ONA:-}" == true ]]; then
    if [[ ! -x "$PREPARE_SCRIPT" ]]; then
        echo "lavish-axi-safe: tailnet preparation helper is not executable: $PREPARE_SCRIPT" >&2
        exit 1
    fi
    ALLOWED_HOST=$($PREPARE_SCRIPT)
    export LAVISH_AXI_HOST=127.0.0.1
    export LAVISH_AXI_LINK_HOST=127.0.0.1
    export LAVISH_AXI_ALLOWED_HOSTS="$ALLOWED_HOST"
    export LAVISH_AXI_NO_OPEN=1
fi

exec npx -y lavish-axi "$@"
