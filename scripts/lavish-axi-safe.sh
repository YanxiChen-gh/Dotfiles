#!/usr/bin/env bash
# Run a Lavish CLI command with loopback-only settings in a remote environment.

set -euo pipefail

if [[ "${IS_ON_ONA:-}" == true ]]; then
    export LAVISH_AXI_HOST=127.0.0.1
    export LAVISH_AXI_LINK_HOST=127.0.0.1
    export LAVISH_AXI_NO_OPEN=1
    unset LAVISH_AXI_ALLOWED_HOSTS
fi

exec npx -y lavish-axi "$@"
