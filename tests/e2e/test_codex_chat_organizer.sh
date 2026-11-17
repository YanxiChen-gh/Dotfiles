#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
python3 "$ROOT/tests/e2e/codex_chat_organizer.py"
python3 "$ROOT/tests/e2e/organizer_enrollment.py"
