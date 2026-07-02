#!/usr/bin/env bash
# Shared helpers for the verify-gate hook. Sourced, not executed directly.
# All predicates are pure-local and fast (no network). Callers fail OPEN on error.

# Kill switch: true (0) when the gate is disabled.
vg_disabled() { [ "${VERIFY_GATE:-on}" = "off" ]; }

# Where the gate logs allow/block decisions (best-effort; never fails a caller).
VG_LOG="${VERIFY_GATE_LOG:-$HOME/.claude/verify-gate.log}"

# Best-effort append to the gate log; never fails the caller.
vg_log() {  # $1=message
  { mkdir -p "$(dirname "$VG_LOG")" 2>/dev/null \
    && printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >>"$VG_LOG"; } 2>/dev/null || true
}
