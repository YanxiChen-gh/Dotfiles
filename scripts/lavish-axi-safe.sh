#!/usr/bin/env bash
# Run a Lavish CLI command with loopback-only settings in a remote environment.

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
    SOURCE_DIR=$(cd "$(dirname "$SOURCE")" && pwd)
    SOURCE=$(readlink "$SOURCE")
    [[ "$SOURCE" == /* ]] || SOURCE="$SOURCE_DIR/$SOURCE"
done
SCRIPT_DIR=$(cd "$(dirname "$SOURCE")" && pwd)

artifact_file=""
case "${1:-}" in
    poll|end) artifact_file="${2:-}" ;;
    *.html|*.htm) artifact_file="$1" ;;
esac
if [[ -n "$artifact_file" ]]; then
    source "$SCRIPT_DIR/lavish-session-env.sh"
    configure_lavish_session_env "$artifact_file"
fi

if [[ "${IS_ON_ONA:-}" == true ]]; then
    export LAVISH_AXI_HOST=127.0.0.1
    export LAVISH_AXI_LINK_HOST=127.0.0.1
    export LAVISH_AXI_NO_OPEN=1
    unset LAVISH_AXI_ALLOWED_HOSTS
fi

exec npx -y lavish-axi "$@"
