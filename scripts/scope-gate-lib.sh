#!/usr/bin/env bash
# Shared helpers for the scope-gate hooks. Sourced, not executed directly.
# All predicates are pure-local and fast (no network). Callers fail OPEN on error.

SG_DATA_DIR="${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}"
SG_BRIEFS_DIR="$SG_DATA_DIR/briefs"
SG_LOG="$SG_DATA_DIR/scope-gate.log"

# Kill switch: true (0) when the gate is disabled.
sg_disabled() { [ "${SCOPE_GATE:-on}" = "off" ]; }

# Autonomous mode: background jobs set CLAUDE_JOB_DIR.
sg_is_autonomous() { [ -n "${CLAUDE_JOB_DIR:-}" ]; }

# Extract a jq path from JSON; empty string on absence/error.
sg_json_field() {  # $1=json $2=jq-path
  printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
}

# Floored (cheap-to-be-wrong) path → allow without a brief: docs, the gate's own
# data/files, and anything OUTSIDE a git work tree. Only code in a repo is worth
# gating; temp files and scratch paths aren't in a repo, so they floor naturally.
# Cheap pattern fast-paths first; the git check is last and fails safe (allow).
sg_is_floored_path() {  # $1=path ; returns 0 = floored (allow)
  case "$1" in
    *.md|*.mdx|*.txt) return 0 ;;
    "$SG_DATA_DIR"/*|*/.agent-maturity-data/*) return 0 ;;
    */scope-gate-*.sh|*/skills/scope-gate/*) return 0 ;;
  esac
  sg_path_in_git_repo "$1" || return 0   # not in a repo → not code → floor it
  return 1
}

# True (0) when the path's nearest existing ancestor dir is inside a git work tree.
# Walks up so a new file in a not-yet-created subdir of a repo is still gated.
sg_path_in_git_repo() {  # $1=path
  local d; d="$(dirname "$1" 2>/dev/null)" || return 1
  while [ -n "$d" ] && [ "$d" != "/" ] && [ ! -d "$d" ]; do d="$(dirname "$d")"; done
  [ -d "$d" ] || return 1
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# The brief store is provisioned/readable.
sg_store_readable() { [ -d "$SG_BRIEFS_DIR" ]; }

# A brief exists for this session (v1 "covers" == exists).
sg_brief_exists() {  # $1=session_id
  [ -n "${1:-}" ] || return 1
  ls "$SG_BRIEFS_DIR"/*"$1"*.json >/dev/null 2>&1
}

# Best-effort append to the gate log; never fails the caller.
sg_log() {  # $1=message
  { mkdir -p "$SG_DATA_DIR" 2>/dev/null && printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >>"$SG_LOG"; } 2>/dev/null || true
}
