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

# --- Task 3: PreToolUse hard hook ---
test_pretooluse(){
  local tmp; tmp="$(mktemp -d)"
  export AGENT_MATURITY_DATA_DIR="$tmp/data"; mkdir -p "$AGENT_MATURITY_DATA_DIR/briefs"
  local PRE="$ROOT/scripts/scope-gate-pretooluse.sh"

  echo '{"session_id":"S1","tool_input":{"file_path":"/r/src/app.ts"}}' | "$PRE" >/dev/null 2>&1
  assert_eq "blocks code edit without brief" 2 "$?"
  grep -q 'block: session=S1' "$AGENT_MATURITY_DATA_DIR/scope-gate.log" 2>/dev/null \
    && ok "block is logged" || no "block is logged"

  echo '{"session_id":"S1","tool_input":{"file_path":"/r/README.md"}}' | "$PRE" >/dev/null 2>&1
  assert_eq "allows floored path" 0 "$?"

  touch "$AGENT_MATURITY_DATA_DIR/briefs/2026-06-15-S1.json"
  echo '{"session_id":"S1","tool_input":{"file_path":"/r/src/app.ts"}}' | "$PRE" >/dev/null 2>&1
  assert_eq "allows code edit with brief" 0 "$?"

  SCOPE_GATE=off bash -c 'echo "{\"session_id\":\"S9\",\"tool_input\":{\"file_path\":\"/r/src/x.ts\"}}" | "$0" >/dev/null 2>&1' "$PRE"
  assert_eq "kill switch allows" 0 "$?"

  printf 'not json' | "$PRE" >/dev/null 2>&1
  assert_eq "malformed input fails open" 0 "$?"

  rm -rf "$AGENT_MATURITY_DATA_DIR/briefs"
  echo '{"session_id":"S2","tool_input":{"file_path":"/r/src/app.ts"}}' | "$PRE" >/dev/null 2>&1
  assert_eq "unreadable store fails open" 0 "$?"

  rm -rf "$tmp"; unset AGENT_MATURITY_DATA_DIR
}
test_pretooluse

# --- Task 4: UserPromptSubmit soft hook ---
test_userpromptsubmit(){
  local UPS="$ROOT/scripts/scope-gate-userpromptsubmit.sh"
  local out
  out="$(echo '{"session_id":"S7","prompt":"add a feature"}' | "$UPS" 2>/dev/null)"
  case "$out" in *"scope-gate"*) ok "UPS injects rubric" ;; *) no "UPS injects rubric" ;; esac
  case "$out" in *"S7"*) ok "UPS injects session id" ;; *) no "UPS injects session id" ;; esac

  out="$(SCOPE_GATE=off bash -c 'echo "{\"session_id\":\"S7\"}" | "$0" 2>/dev/null' "$UPS")"
  assert_eq "UPS silent when disabled" "" "$out"
}
test_userpromptsubmit

# --- Task 5: settings.json hook registration (idempotent, non-clobbering) ---
test_register(){
  local tmp; tmp="$(mktemp -d)"
  local cfg="$tmp/settings.json"
  cat >"$cfg" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]},"theme":"dark"}
JSON
  bash "$ROOT/scripts/scope-gate-register.sh" "$cfg" >/dev/null 2>&1
  bash "$ROOT/scripts/scope-gate-register.sh" "$cfg" >/dev/null 2>&1   # second run = idempotent

  assert_eq "rtk Bash hook preserved" "1" \
    "$(jq '[.hooks.PreToolUse[]|select(.matcher=="Bash")]|length' "$cfg")"
  assert_eq "pretooluse registered once" "1" \
    "$(jq '[.hooks.PreToolUse[].hooks[]|select(.command|test("scope-gate-pretooluse"))]|length' "$cfg")"
  assert_eq "userpromptsubmit registered once" "1" \
    "$(jq '[.hooks.UserPromptSubmit[].hooks[]|select(.command|test("scope-gate-userpromptsubmit"))]|length' "$cfg")"
  assert_eq "theme preserved" '"dark"' "$(jq '.theme' "$cfg")"
  rm -rf "$tmp"
}
test_register

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
