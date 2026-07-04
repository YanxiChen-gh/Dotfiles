#!/usr/bin/env bash
# PreToolUse(Bash) gate: block `gh pr create` / `gh pr edit --body` when an LLM judge grades the
# PR body as bloated against pr-authoring.md. This is the Spec lever that makes the guide land on
# the *first* draft instead of being cleaned up after the fact by /simplify-pr — the body is
# composed by the time `gh pr create` runs, so the earliest a hook can intervene is here, blocking
# before the PR object exists (no GitHub churn). check.py runs the judge via `claude -p`.
#
# Exit 0 = allow; exit 2 = block (Claude Code feeds stderr back to the agent).
# Fails OPEN on any error — a broken gate must never wedge PR creation.
#
# Personal harness lever. Assets it points at: ~/dotfiles/claude/pr-authoring.md + pr-examples.md.
# Kill switch:  export PR_AUTHORING_GATE=off
# Retirement:   when /maturity-review's ablation shows PR-bloat/quality-noise interventions
#               flat-at-floor without the gate (the model writes clean PR bodies by default),
#               delete this hook + its install.sh registration.
set -uo pipefail

[ "${PR_AUTHORING_GATE:-on}" = "off" ] && exit 0     # kill switch
[ "${PAG_JUDGING:-}" = "1" ] && exit 0               # don't gate the judge subprocess itself

command -v python3 >/dev/null 2>&1 || exit 0         # no python → fail open
command -v claude  >/dev/null 2>&1 || exit 0         # no judge available → fail open

DIR="$(cd "$(dirname "$0")" && pwd)"
# `python3 <missing-file>` exits 2, which Claude Code reads as a BLOCK — so a missing check.py
# would wedge PR creation. Guard it: absent script → fail open.
[ -f "$DIR/pr-authoring-gate-check.py" ] || exit 0
input="$(cat 2>/dev/null)" || exit 0

# check.py decides: exit 2 + stderr message to block, exit 0 to allow. It fails open
# (exit 0) on any error — including a judge timeout/failure — so it can only ever block a
# body the judge actually graded as bloated.
printf '%s' "$input" | PAG_LOG="${PR_AUTHORING_GATE_LOG:-$HOME/.claude/pr-authoring-gate.log}" python3 "$DIR/pr-authoring-gate-check.py"
exit $?
