#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
python3 "$ROOT/tests/e2e/session_hub_fixtures.py"
