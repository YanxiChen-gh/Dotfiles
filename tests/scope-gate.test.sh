#!/usr/bin/env bash
# Plain-bash fixture tests for the scope gate. Run: bash tests/scope-gate.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
assert_eq(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want [$2], got [$3])"; fi; }

# --- Task 1: ensure-maturity-data creates briefs/ ---
test_briefs_dir_created(){
  local tmp; tmp="$(mktemp -d)"
  # Simulate an already-provisioned data repo (skip the gh clone path).
  mkdir -p "$tmp/data/.git"
  AGENT_MATURITY_DATA_DIR="$tmp/data" \
    AGENT_MATURITY_DIR="$tmp/dot" \
    bash "$ROOT/scripts/ensure-maturity-data.sh" >/dev/null 2>&1
  if [ -d "$tmp/data/briefs" ]; then ok "ensure-maturity-data creates briefs/"; else no "ensure-maturity-data creates briefs/"; fi
  rm -rf "$tmp"
}
test_briefs_dir_created

# --- Task 2: scope-gate-lib.sh predicates ---
test_lib(){
  local tmp; tmp="$(mktemp -d)"
  export AGENT_MATURITY_DATA_DIR="$tmp/data"; mkdir -p "$AGENT_MATURITY_DATA_DIR/briefs"
  # shellcheck source=/dev/null
  . "$ROOT/scripts/scope-gate-lib.sh"

  ( SCOPE_GATE=off; sg_disabled ) && ok "sg_disabled true when off" || no "sg_disabled true when off"
  ( SCOPE_GATE=on;  sg_disabled ) && no "sg_disabled false when on" || ok "sg_disabled false when on"

  ( CLAUDE_JOB_DIR=/x; sg_is_autonomous ) && ok "autonomous when CLAUDE_JOB_DIR set" || no "autonomous when CLAUDE_JOB_DIR set"
  ( unset CLAUDE_JOB_DIR; sg_is_autonomous ) && no "interactive when CLAUDE_JOB_DIR unset" || ok "interactive when CLAUDE_JOB_DIR unset"

  assert_eq "json_field extracts file_path" "/a/b.ts" \
    "$(sg_json_field '{"tool_input":{"file_path":"/a/b.ts"}}' '.tool_input.file_path')"
  assert_eq "json_field empty on missing" "" \
    "$(sg_json_field '{"x":1}' '.tool_input.file_path')"

  sg_is_floored_path "/r/README.md" && ok "floor: .md" || no "floor: .md"
  sg_is_floored_path "$AGENT_MATURITY_DATA_DIR/briefs/x.json" && ok "floor: data dir" || no "floor: data dir"
  sg_is_floored_path "/r/src/app.ts" && no "floor: rejects code" || ok "floor: rejects code"

  sg_store_readable && ok "store readable when briefs/ exists" || no "store readable when briefs/ exists"
  rm -rf "$AGENT_MATURITY_DATA_DIR/briefs"
  sg_store_readable && no "store unreadable when briefs/ gone" || ok "store unreadable when briefs/ gone"
  mkdir -p "$AGENT_MATURITY_DATA_DIR/briefs"

  sg_brief_exists "S1" && no "no brief for S1 yet" || ok "no brief for S1 yet"
  touch "$AGENT_MATURITY_DATA_DIR/briefs/2026-06-15-S1.json"
  sg_brief_exists "S1" && ok "brief found for S1" || no "brief found for S1"
  sg_brief_exists "" && no "empty session never matches" || ok "empty session never matches"

  rm -rf "$tmp"; unset AGENT_MATURITY_DATA_DIR
}
test_lib

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
