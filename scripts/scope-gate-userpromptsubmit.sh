#!/usr/bin/env bash
# UserPromptSubmit soft half: stdout is added to the model's context.
# Injects the triage rubric + the session id (so /scope-gate can name the brief
# and the PreToolUse hook can match it). Silent when disabled. Never blocks.
set -uo pipefail

LIB="$(dirname "$0")/scope-gate-lib.sh"
# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || exit 0

input="$(cat 2>/dev/null)" || exit 0
sg_disabled && exit 0
command -v jq >/dev/null 2>&1 || exit 0

session="$(sg_json_field "$input" '.session_id')"

cat <<MSG
[scope-gate] (session: ${session})
Before editing code on a NON-TRIVIAL task, run /scope-gate first. Non-trivial = any
approach/design choice, a new/changed public interface, multi-file or multi-system
work, a "make it X" architectural ask, multi-part (PR-decomposition) work, or you are
unsure. Default to non-trivial when unsure. Trivial (one obvious, cheaply-reversible
change, no new interface, no approach fork) → just proceed. If a new non-trivial task
starts mid-session, re-run /scope-gate. When the skill writes the brief, name it
\$AGENT_MATURITY_DATA_DIR/briefs/<YYYY-MM-DD>-${session}.json
MSG
exit 0
