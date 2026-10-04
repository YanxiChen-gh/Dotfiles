#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook: nudge the model to apply the comment bar right after it
# writes comments, because current models (Opus 4.8) over-comment by default and prose
# guidance alone under-corrects. Fires only on JS/TS edits that actually added comment
# syntax, and injects a terse reminder (suppressed from the transcript).
#
# Personal harness lever. Full bar: ~/dotfiles/claude/pr-authoring.md.
# Kill switch:  export COMMENT_BAR_HOOK=off
# Retirement:   model-specific - when the model stops over-commenting (verify via the
#               agent-maturity `verbose-output` tag at a model upgrade), delete this hook
#               and its install.sh registration. A harness that only grows is one you've
#               stopped reading.
set -euo pipefail

[ "${COMMENT_BAR_HOOK:-on}" = "off" ] && exit 0

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')

case "$file" in
  *.ts | *.tsx | *.js | *.jsx) ;;
  *) exit 0 ;;
esac

# Only fire when the edit introduced comment syntax (cheap heuristic; false positives are harmless).
body=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // ""')
printf '%s' "$body" | grep -qE '//|/\*|^[[:space:]]*\*' || exit 0

cat <<'JSON'
{"suppressOutput":true,"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Comment self-check: read ~/dotfiles/claude/pr-authoring.md and apply section 4 to the comments in this edit and section 2 to any changed unit tests. Fix concrete violations before handoff; do not remove necessary explanations or protection for real behavior."}}
JSON
