#!/usr/bin/env bash
# PreToolUse(Bash) gate: block `gh pr create` when the PR body lacks verification
# evidence AND an independent-grading section. This is the Trust L2→L3 lever — the
# rubric names `gh pr create` as the "before your eyes" boundary where verification
# should gate completion. The gate only checks that a review happened; the primed
# workflow (CLAUDE.md) makes it actually happen, and the independent review itself is
# a clean-context subagent the main agent dispatches (a shell hook can't spawn one).
#
# Exit 0 = allow; exit 2 = block (Claude Code feeds stderr back to the agent).
# Fails OPEN on any error — a broken gate must never wedge PR creation.
#
# Personal harness lever. Assets it points at: ~/dotfiles/shared-skills/full-verification-workflow.
# Kill switch:  export VERIFY_GATE=off
# Retirement:   when /maturity-review's ablation shows verify-fail/quality-noise
#               interventions flat-at-floor without the gate (the model self-verifies
#               and self-reviews by default), delete this hook + its install.sh
#               registration. A harness that only grows is one you've stopped reading.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/verify-gate-lib.sh" 2>/dev/null || exit 0   # lib missing → fail open

vg_disabled && exit 0                                # kill switch

command -v python3 >/dev/null 2>&1 || { vg_log "fail-open: python3 missing"; exit 0; }

# `python3 <missing-file>` exits 2, which Claude Code reads as a BLOCK — a missing check.py
# would wedge PR creation. Guard it: absent script → fail open.
[ -f "$DIR/verify-gate-check.py" ] || { vg_log "fail-open: check.py missing"; exit 0; }

input="$(cat 2>/dev/null)" || exit 0

# check.py decides: exit 2 + stderr message to block, exit 0 to allow. It fails open
# (exit 0) on any parse error, so the gate can only ever block a deliberate miss.
printf '%s' "$input" | VG_LOG="$VG_LOG" python3 "$DIR/verify-gate-check.py"
exit $?
