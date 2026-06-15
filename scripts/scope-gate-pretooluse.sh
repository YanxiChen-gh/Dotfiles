#!/usr/bin/env bash
# PreToolUse(Edit|Write) hard backstop for the scope gate.
# Exit 0 = allow; exit 2 = block (Claude Code feeds stderr back to the agent).
# Fails OPEN on any error — a broken gate must never wedge editing.
set -uo pipefail

LIB="$(dirname "$0")/scope-gate-lib.sh"
# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || exit 0          # lib missing → fail open

input="$(cat 2>/dev/null)" || exit 0

sg_disabled && exit 0                    # kill switch

command -v jq >/dev/null 2>&1 || { sg_log "fail-open: jq missing"; exit 0; }

path="$(sg_json_field "$input" '.tool_input.file_path')"
session="$(sg_json_field "$input" '.session_id')"

# Floored, cheap-to-be-wrong paths (incl. the brief writes themselves) → allow.
if [ -n "$path" ] && sg_is_floored_path "$path"; then
  sg_log "floored allow: $path"
  exit 0
fi

# Can't identify the task → fail open (don't block on malformed/partial input).
[ -n "$session" ] || { sg_log "fail-open: no session_id"; exit 0; }

# Store not provisioned yet → fail open (bootstrap / broken env).
sg_store_readable || { sg_log "fail-open: brief store unreadable"; exit 0; }

# Brief recorded for this session → allow.
sg_brief_exists "$session" && exit 0

sg_log "block: session=$session path=$path"
cat >&2 <<'MSG'
⛔ Scope gate: no scoping decision recorded for this task.

Before editing code, run /scope-gate to produce a scoping brief: restate the task
+ pass-to-pass acceptance checks, propose a PR-decomposition if multi-part, and
batch any genuine scope questions. If the task is genuinely trivial, the skill's
--trivial path records that in one line. Then retry the edit.
MSG
exit 2
