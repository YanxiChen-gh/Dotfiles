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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
