#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook: nudge the model to apply the comment bar right after it
# writes comments, because current models (Opus 4.8) over-comment by default and prose
# guidance alone under-corrects. Fires only on JS/TS edits that actually added comment
# syntax, and injects a terse reminder (suppressed from the transcript).
#
# Personal harness lever. Full bar: ~/dotfiles/claude/pr-authoring.md.
# Kill switch:  export COMMENT_BAR_HOOK=off
# Retirement:   model-specific — when the model stops over-commenting (verify via the
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
{"suppressOutput":true,"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Comment self-check (current models over-comment by default): re-read the comments in the edit you just made and delete any that narrate the change ('we used to…', 'now X', 'Phase 0'), restate what the code already says, are obvious from the symbol name, or only re-verify a library/type. Keep only the non-obvious *why* (gotcha, workaround, external constraint). Same bar for tests — no coverage-only tests. Full guide: ~/dotfiles/claude/pr-authoring.md."}}
JSON
