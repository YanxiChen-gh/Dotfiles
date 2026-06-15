#!/usr/bin/env bash
# Append one intervention to the agent-maturity log. This is the raw signal the
# /maturity-review skill scores against — keep it cheap so you actually log.
#
# Usage:
#   log-intervention.sh <type> "<note>" [cost_min]
#     type      correction | clarification | unblock
#                 correction    = you fixed/redid agent output  -> Trust
#                 clarification = you re-scoped / answered mid-task -> Spec
#                 unblock       = you got a stuck agent moving    -> Babysit
#     note      short free-text description
#     cost_min  optional integer minutes the intervention cost (default 0)
#
# Suggested shell alias (add to .zshrc.local):
#   alias li='~/dotfiles/scripts/log-intervention.sh'
# Then: li correction "rewrote the auth guard the agent got backwards" 15

set -euo pipefail

LOG="${AGENT_MATURITY_LOG:-$HOME/dotfiles/claude/agent-maturity/interventions.jsonl}"

type="${1:-}"
note="${2:-}"
cost="${3:-0}"

case "$type" in
  correction|clarification|unblock) ;;
  *)
    echo "error: type must be correction | clarification | unblock (got '${type:-<empty>}')" >&2
    echo "usage: log-intervention.sh <type> \"<note>\" [cost_min]" >&2
    exit 2
    ;;
esac

if [ -z "$note" ]; then
  echo "error: note is required" >&2
  exit 2
fi

date_iso="$(date +%F)"
repo="$(git rev-parse --show-toplevel 2>/dev/null | xargs -r basename || echo unknown)"

# Escape the note for JSON (quotes + backslashes).
esc_note="$(printf '%s' "$note" | sed 's/\\/\\\\/g; s/"/\\"/g')"

printf '{"date":"%s","repo":"%s","type":"%s","cost_min":%s,"source":"manual","note":"%s"}\n' \
  "$date_iso" "$repo" "$type" "${cost:-0}" "$esc_note" >> "$LOG"

echo "logged $type ($repo): $note"
