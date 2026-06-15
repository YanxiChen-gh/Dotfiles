# Scope Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pre-execution scoping gate — deterministic hooks that force a recorded triage decision before code on non-trivial tasks — per `claude/agent-maturity/specs/2026-06-15-scope-gate-design.md`.

**Architecture:** Two bash hooks share a sourced library. `UserPromptSubmit` (soft) injects the triage rubric + the session id. `PreToolUse(Edit|Write)` (hard) blocks the first code edit until a brief exists for the session. The `scope-gate` skill produces the brief (the marker + measurement artifact) in the private data repo. `install.sh` registers both hooks idempotently. Everything fails OPEN.

**Tech Stack:** Bash, `jq` (JSON parsing, present at `/usr/bin/jq`), `python3` (settings.json merge), Claude Code hooks + skills. Tests are plain bash (no bats).

---

## File Structure

- **Create** `scripts/scope-gate-lib.sh` — sourced helpers (kill switch, JSON extract, floor check, brief lookup, store-readable, autonomous detect, log). One responsibility: pure-local predicates shared by both hooks.
- **Create** `scripts/scope-gate-pretooluse.sh` — hard backstop. Decision order → allow (exit 0) / block (exit 2).
- **Create** `scripts/scope-gate-userpromptsubmit.sh` — soft half. Injects rubric + session id; silent when disabled.
- **Create** `tests/scope-gate.test.sh` — fixture-driven tests for the lib, both hooks, and the install merge. Grows across Tasks 2–5.
- **Create** `claude/skills/scope-gate/SKILL.md` — the brief-producing skill (content; mode handling; `--trivial` path; retirement-trigger header).
- **Modify** `scripts/ensure-maturity-data.sh` — `mkdir -p "$DATA/briefs"`.
- **Modify** `install.sh` — add `setup_scope_gate()` + call it.
- **Modify** `claude/skills/harvest-interventions/SKILL.md` — add a briefs-reading step + the trailer caveat.
- **Modify** `claude/agent-maturity/tracker.md` (private repo via symlink) — retirement trigger + changelog entry.

Refines spec component C: the `UserPromptSubmit` hook injects `session_id` (from its stdin JSON) so the skill names the brief deterministically and the `PreToolUse` hook matches it.

---

### Task 1: Briefs directory plumbing

**Files:**
- Modify: `scripts/ensure-maturity-data.sh:23`
- Test: `tests/scope-gate.test.sh` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/scope-gate.test.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scope-gate.test.sh`
Expected: FAIL — "ensure-maturity-data creates briefs/" (the dir isn't created yet).

- [ ] **Step 3: Implement**

In `scripts/ensure-maturity-data.sh`, after line 23 (`mkdir -p "$DOTDIR"`), add:

```bash
mkdir -p "$DATA/briefs"        # scope-gate briefs (marker + measurement artifact)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scope-gate.test.sh`
Expected: PASS — "1 passed, 0 failed".

- [ ] **Step 5: Commit**

```bash
git add scripts/ensure-maturity-data.sh tests/scope-gate.test.sh
git commit -m "scope-gate: create briefs/ dir in maturity data store"
```

---

### Task 2: Shared hook library

**Files:**
- Create: `scripts/scope-gate-lib.sh`
- Test: `tests/scope-gate.test.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/scope-gate.test.sh` (before the final `printf`/exit lines):

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scope-gate.test.sh`
Expected: FAIL — sourcing `scope-gate-lib.sh` errors (file does not exist).

- [ ] **Step 3: Implement**

Create `scripts/scope-gate-lib.sh`:

```bash
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

# Floored (cheap-to-be-wrong) path: docs, the gate's own data, scope-gate files.
sg_is_floored_path() {  # $1=path
  case "$1" in
    *.md|*.mdx|*.txt) return 0 ;;
    "$SG_DATA_DIR"/*|*/.agent-maturity-data/*) return 0 ;;
    */scope-gate-*.sh|*/skills/scope-gate/*) return 0 ;;
    *) return 1 ;;
  esac
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scope-gate.test.sh`
Expected: PASS — all Task 1 + Task 2 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/scope-gate-lib.sh tests/scope-gate.test.sh
git commit -m "scope-gate: shared hook library (predicates + logging)"
```

---

### Task 3: PreToolUse hard hook

**Files:**
- Create: `scripts/scope-gate-pretooluse.sh`
- Test: `tests/scope-gate.test.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/scope-gate.test.sh`:

```bash
# --- Task 3: PreToolUse hard hook ---
test_pretooluse(){
  local tmp; tmp="$(mktemp -d)"
  export AGENT_MATURITY_DATA_DIR="$tmp/data"; mkdir -p "$AGENT_MATURITY_DATA_DIR/briefs"
  local PRE="$ROOT/scripts/scope-gate-pretooluse.sh"

  echo '{"session_id":"S1","tool_input":{"file_path":"/r/src/app.ts"}}' | "$PRE" >/dev/null 2>&1
  assert_eq "blocks code edit without brief" 2 "$?"

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scope-gate.test.sh`
Expected: FAIL — the hook script does not exist (non-zero exit, assertions fail).

- [ ] **Step 3: Implement**

Create `scripts/scope-gate-pretooluse.sh`:

```bash
#!/usr/bin/env bash
# PreToolUse(Edit|Write) hard backstop for the scope gate.
# Exit 0 = allow; exit 2 = block (Claude Code feeds stderr back to the agent).
# Fails OPEN on any error — a broken gate must never wedge editing.
set -uo pipefail

LIB="$(dirname "$0")/scope-gate-lib.sh"
# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || exit 0          # lib missing → fail open

input="$(cat 2>/dev/null)" || exit 0

sg_disabled && exit 0                    # kill switch

command -v jq >/dev/null 2>&1 || { sg_log "fail-open: jq missing"; exit 0; }

path="$(sg_json_field "$input" '.tool_input.file_path')"
session="$(sg_json_field "$input" '.session_id')"

# Floored, cheap-to-be-wrong paths (incl. the brief writes themselves) → allow.
if [ -n "$path" ] && sg_is_floored_path "$path"; then
  sg_log "floored allow: $path"
  exit 0
fi

# Can't identify the task → fail open (don't block on malformed/partial input).
[ -n "$session" ] || { sg_log "fail-open: no session_id"; exit 0; }

# Store not provisioned yet → fail open (bootstrap / broken env).
sg_store_readable || { sg_log "fail-open: brief store unreadable"; exit 0; }

# Brief recorded for this session → allow.
sg_brief_exists "$session" && exit 0

cat >&2 <<'MSG'
⛔ Scope gate: no scoping decision recorded for this task.

Before editing code, run /scope-gate to produce a scoping brief: restate the task
+ pass-to-pass acceptance checks, propose a PR-decomposition if multi-part, and
batch any genuine scope questions. If the task is genuinely trivial, the skill's
--trivial path records that in one line. Then retry the edit.
MSG
exit 2
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scope-gate.test.sh`
Expected: PASS — all assertions through Task 3.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/scope-gate-pretooluse.sh
git add scripts/scope-gate-pretooluse.sh tests/scope-gate.test.sh
git commit -m "scope-gate: PreToolUse hard backstop (blocks code without a brief)"
```

---

### Task 4: UserPromptSubmit soft hook

**Files:**
- Create: `scripts/scope-gate-userpromptsubmit.sh`
- Test: `tests/scope-gate.test.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/scope-gate.test.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scope-gate.test.sh`
Expected: FAIL — the UPS script does not exist.

- [ ] **Step 3: Implement**

Create `scripts/scope-gate-userpromptsubmit.sh`:

```bash
#!/usr/bin/env bash
# UserPromptSubmit soft half: stdout is added to the model's context.
# Injects the triage rubric + the session id (so /scope-gate can name the brief
# and the PreToolUse hook can match it). Silent when disabled. Never blocks.
set -uo pipefail

LIB="$(dirname "$0")/scope-gate-lib.sh"
# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || exit 0

input="$(cat 2>/dev/null)" || exit 0
sg_disabled && exit 0
command -v jq >/dev/null 2>&1 || exit 0

session="$(sg_json_field "$input" '.session_id')"

cat <<MSG
[scope-gate] (session: ${session})
Before editing code on a NON-TRIVIAL task, run /scope-gate first. Non-trivial = any
approach/design choice, a new/changed public interface, multi-file or multi-system
work, a "make it X" architectural ask, multi-part (PR-decomposition) work, or you are
unsure. Default to non-trivial when unsure. Trivial (one obvious, cheaply-reversible
change, no new interface, no approach fork) → just proceed. If a new non-trivial task
starts mid-session, re-run /scope-gate. When the skill writes the brief, name it
\$AGENT_MATURITY_DATA_DIR/briefs/<YYYY-MM-DD>-${session}.json
MSG
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scope-gate.test.sh`
Expected: PASS — all assertions through Task 4.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/scope-gate-userpromptsubmit.sh
git add scripts/scope-gate-userpromptsubmit.sh tests/scope-gate.test.sh
git commit -m "scope-gate: UserPromptSubmit soft hook (rubric + session id)"
```

---

### Task 5: Register hooks in install.sh

**Files:**
- Modify: `install.sh` (add `setup_scope_gate`; call it near `setup_rtk`)
- Test: `tests/scope-gate.test.sh`

- [ ] **Step 1: Write the failing test**

Append to `tests/scope-gate.test.sh`. This tests the merge logic in isolation by extracting it to a helper the installer also uses; the test invokes that helper against a temp settings file.

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scope-gate.test.sh`
Expected: FAIL — `scripts/scope-gate-register.sh` does not exist.

- [ ] **Step 3: Implement the registration helper**

Create `scripts/scope-gate-register.sh` (used by both the test and `install.sh`, keeping the merge DRY):

```bash
#!/usr/bin/env bash
# Idempotently register the scope-gate hooks into a Claude settings.json.
# Non-clobbering: preserves existing hooks (e.g. the RTK Bash PreToolUse entry).
# Usage: scope-gate-register.sh [path-to-settings.json]   (default: ~/.claude/settings.json)
set -uo pipefail
CFG="${1:-$HOME/.claude/settings.json}"
command -v python3 >/dev/null 2>&1 || { echo "scope-gate-register: python3 required" >&2; exit 1; }

python3 - "$CFG" <<'PY'
import json, os, sys
path = os.path.expanduser(sys.argv[1])
home = os.path.expanduser("~")
pre_cmd = f"{home}/dotfiles/scripts/scope-gate-pretooluse.sh"
ups_cmd = f"{home}/dotfiles/scripts/scope-gate-userpromptsubmit.sh"

os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})

def has_cmd(arr, cmd):
    return any(h.get("command") == cmd for entry in arr for h in entry.get("hooks", []))

pre = hooks.setdefault("PreToolUse", [])
if not has_cmd(pre, pre_cmd):
    pre.append({"matcher": "Edit|Write", "hooks": [{"type": "command", "command": pre_cmd}]})

ups = hooks.setdefault("UserPromptSubmit", [])
if not has_cmd(ups, ups_cmd):
    ups.append({"hooks": [{"type": "command", "command": ups_cmd}]})

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scope-gate.test.sh`
Expected: PASS — all assertions through Task 5.

- [ ] **Step 5: Wire into install.sh**

In `install.sh`, add this function next to `setup_rtk` (after line 656):

```bash
# Register the scope-gate hooks in ~/.claude/settings.json (idempotent, non-clobbering).
setup_scope_gate() {
    echo "Setting up scope-gate hooks..."
    chmod +x "$HOME/dotfiles/scripts/scope-gate-pretooluse.sh" \
             "$HOME/dotfiles/scripts/scope-gate-userpromptsubmit.sh" 2>/dev/null || true
    if bash "$HOME/dotfiles/scripts/scope-gate-register.sh" 2>/dev/null; then
        echo "✅ scope-gate hooks registered for Claude Code"
    else
        echo "⚠️  scope-gate hook registration failed (run: scripts/scope-gate-register.sh)"
    fi
}
```

Then find where `setup_rtk` is invoked in the main flow and add a call to `setup_scope_gate` immediately after it. Locate the call site:

Run: `grep -n 'setup_rtk$' install.sh`
Add `    setup_scope_gate` on the line after the `setup_rtk` invocation (matching indentation).

- [ ] **Step 6: Verify install wiring syntactically**

Run: `bash -n install.sh && grep -n 'setup_scope_gate' install.sh`
Expected: no syntax error; two matches (definition + call site).

- [ ] **Step 7: Commit**

```bash
chmod +x scripts/scope-gate-register.sh
git add scripts/scope-gate-register.sh install.sh tests/scope-gate.test.sh
git commit -m "scope-gate: register hooks via install.sh (idempotent settings merge)"
```

---

### Task 6: The scope-gate skill

**Files:**
- Create: `claude/skills/scope-gate/SKILL.md`

No unit test (a skill is a prompt). Its contract is the brief schema, validated in Task 9. This task is a single authored artifact + commit.

- [ ] **Step 1: Write the skill**

Create `claude/skills/scope-gate/SKILL.md`:

````markdown
---
name: scope-gate
description: Produce a pre-execution scoping brief before writing code on a non-trivial task — restate the task with pass-to-pass acceptance checks, propose a PR-decomposition when multi-part, and batch genuine scope questions up front. Invoked by the agent when it self-classifies a task as non-trivial, or when the scope-gate PreToolUse hook blocks an edit. A Spec L2→L3/L4 lever in the agent-maturity system.
---

# Scope Gate

Force scoping **before** code on non-trivial tasks, to cut the scope-redirection
clarifications that otherwise land after an approach is already chosen. Produces a
**brief** that is both the gate marker (the PreToolUse hook checks for it) and the
measurement artifact (`/harvest-interventions` reads it).

**This is a Spec L2→L3/L4 lever. Retirement trigger:** when agent-initiated
scope-question precision is high AND clarifications/PR is flat, this gate is no longer
load-bearing — `/maturity-review`'s ablation check should flag it for removal.

## When this runs

- The agent self-classified the current task as **non-trivial** (see the injected
  triage rubric), or
- The `scope-gate-pretooluse.sh` hook **blocked** an Edit/Write with "no scoping
  decision recorded".

## Triage first

Apply the rubric. **Non-trivial** if any: an approach/design choice; a new/changed
public interface, type, endpoint, or schema; multi-file or multi-system work; a
"make it X" architectural ask; multi-part (PR-decomposition) work; or you are unsure.
**Default to non-trivial when unsure.** **Trivial** = one obvious, cheaply-reversible
change, no new interface, no approach fork.

If trivial, take the **`--trivial` path**: write a brief with `"triage":"trivial"` and
a one-line `trivial_reason`, then proceed to code. Do not over-scope trivial work.

## Procedure (non-trivial)

1. **Provision the data store** (fast no-op once set up):

       bash ~/dotfiles/scripts/ensure-maturity-data.sh

   If it reports gh isn't authenticated / repo inaccessible, tell the user and stop
   (the brief can't be persisted; the hook will fail open so editing isn't wedged).

2. **Restate** the task in one line + **pass-to-pass acceptance checks** — concrete,
   checkable conditions that define done.

3. **Propose a PR-decomposition** if the work is multi-part: an ordered list of
   independently-shippable parts.

4. **Batch genuine scope questions** — only real blockers and approach forks
   (precision over volume). For each, either get an answer or record an explicit
   assumption.

5. **Approval (mode-dependent):**
   - **Interactive** (no `$CLAUDE_JOB_DIR`): present the brief, ask the scope
     questions, and **wait for approval** before writing code.
   - **Autonomous** (`$CLAUDE_JOB_DIR` set): do **not** wait. Record each open
     question as an `assumed` resolution with its assumption, proceed to code, and
     **surface the assumptions in the PR description** for async review.

6. **Write the brief** with the Write tool (this path is floored, so the hook allows
   it) to:

       $AGENT_MATURITY_DATA_DIR/briefs/<YYYY-MM-DD>-<session_id>.json

   Use the `session_id` from the `[scope-gate] (session: …)` line the
   UserPromptSubmit hook injected. If you don't have it, check that line in context.
   Schema:

   ```json
   {
     "session_id": "...",
     "created_at": "ISO-8601",
     "mode": "interactive | autonomous",
     "task_descriptor": "one line",
     "triage": "non-trivial | trivial",
     "trivial_reason": "string, present iff triage==trivial",
     "acceptance_checks": ["...", "..."],
     "pr_decomposition": ["...", "..."],
     "questions": [
       {"q": "...", "resolution": "answered | assumed", "assumption": "string if assumed"}
     ],
     "covers": ["path or glob this brief scopes"]
   }
   ```

7. **Sync** so the brief persists off the ephemeral env:

       bash ~/dotfiles/scripts/sync-maturity-data.sh "scope-gate: brief <session_id>"

8. **Proceed to code.** Retry the edit that was blocked (the hook now finds the brief).

## Notes

- The brief is intentionally lightweight — delegate deep design to
  `superpowers:brainstorming` and deep planning to `superpowers:writing-plans` when a
  task warrants them. This skill is the *gate*, not a replacement for those.
- One brief per session covers the session (v1). If a genuinely new non-trivial task
  begins mid-session, re-run this skill to write a fresh brief.
````

- [ ] **Step 2: Verify frontmatter parses**

Run: `head -3 claude/skills/scope-gate/SKILL.md`
Expected: starts with `---`, then `name: scope-gate`. (No `disable-model-invocation` — this skill is meant to be model-invoked.)

- [ ] **Step 3: Commit**

```bash
git add claude/skills/scope-gate/SKILL.md
git commit -m "scope-gate: add the brief-producing skill"
```

---

### Task 7: Harvester wiring + trailer caveat

**Files:**
- Modify: `claude/skills/harvest-interventions/SKILL.md`

- [ ] **Step 1: Add a briefs-reading step**

In `claude/skills/harvest-interventions/SKILL.md`, after the `### 0b` section (cross-env evidence refresh) and before `### 1. Dispatch a mining subagent`, insert:

```markdown
### 0c. Read scope-gate briefs (the gate's measurement substrate)

If `$AGENT_MATURITY_DATA_DIR/briefs/` has entries in the window, summarize them for
`/maturity-review`:

- **scoped-before-code rate** = non-trivial briefs ÷ (non-trivial briefs + non-trivial
  tasks that reached code with no brief, inferred from transcripts). Report the count
  of briefs by `triage`.
- **Ask-F1 inputs** — count batched up-front questions in briefs vs. clarifications
  that still landed *later* in the same session's transcript. Falling later-clarifications
  with steady up-front question precision = the gate working.

Report these as a short block; `/maturity-review` consumes them in its Spec scoring and
ablation check. If `briefs/` is empty (gate not yet exercised), say so.
```

- [ ] **Step 2: Add the trailer caveat to source B**

In the same file, in the mining subagent's instructions, find the **B. Git history**
paragraph (the one keying on `Co-Authored-By: Claude`). Append:

```markdown
> **Caveat (2026-06-15):** the `Co-Authored-By: Claude` trailer is no longer a reliable
> agent-vs-human signal — treat all PRs as AI-generated. Use this source only as weak
> corroboration for corrections; prefer transcript turns (source A) and scope-gate
> briefs (step 0c) as the authoritative per-task signal. The north-star denominator is
> "merged PRs", not "merged agent-PRs".
```

- [ ] **Step 3: Verify the edits landed**

Run: `grep -n '0c. Read scope-gate briefs\|Caveat (2026-06-15)' claude/skills/harvest-interventions/SKILL.md`
Expected: two matches.

- [ ] **Step 4: Commit**

```bash
git add claude/skills/harvest-interventions/SKILL.md
git commit -m "scope-gate: harvester reads briefs; weaken Co-Authored-By trailer signal"
```

---

### Task 8: Tracker retirement trigger + changelog

**Files:**
- Modify: `claude/agent-maturity/tracker.md` (symlink into the private data repo — edit the real file)

- [ ] **Step 1: Provision the data store**

Run: `bash ~/dotfiles/scripts/ensure-maturity-data.sh`
Expected: "maturity data ready". If gh is unauthenticated, stop and tell the user.

- [ ] **Step 2: Add a retirement trigger note + changelog entry**

Edit `~/.agent-maturity-data/tracker.md` (the real path, not via the symlink). Under the
**## Recommended next move** section, append:

```markdown
**Retirement trigger (scope-gate):** retire the gate when agent-initiated scope-question
precision is high AND clarifications/PR is flat — at that point the gate is no longer
load-bearing and the ablation check should flag it for removal.
```

And append to the **## Changelog**:

```markdown
- **2026-06-15** — Built the scope-gate (spec + plan + hooks + skill): deterministic
  `UserPromptSubmit` (rubric + session id) and `PreToolUse(Edit|Write)` (hard backstop)
  hooks enforce a recorded triage decision before code; the `scope-gate` skill writes a
  brief that is both the marker and the measurement artifact. Kill switch `SCOPE_GATE=off`;
  fails OPEN. First measured/removable/rung-scoped intervention. _Metric impact: TBD —
  measure clarifications/PR vs 1.7 baseline next review._
```

- [ ] **Step 3: Sync the private data store**

Run: `bash ~/dotfiles/scripts/sync-maturity-data.sh "scope-gate: retirement trigger + changelog"`
Expected: "maturity data synced".

(No dotfiles commit — tracker.md lives in the private repo.)

---

### Task 9: Integration verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/scope-gate.test.sh`
Expected: all passed, exit 0.

- [ ] **Step 2: Syntax + lint the shell**

Run: `for f in scripts/scope-gate-*.sh; do bash -n "$f" && echo "ok $f"; done`
Expected: `ok` for each.
Run (if shellcheck present): `command -v shellcheck && shellcheck scripts/scope-gate-*.sh || echo "shellcheck not installed; skipped"`
Expected: no errors (warnings acceptable; fix any error-level finding).

- [ ] **Step 3: Live smoke test — block then allow**

Register the hooks into a throwaway settings file and exercise the real hook end-to-end:

```bash
# Block: code edit, fresh session, no brief
echo '{"session_id":"SMOKE","tool_input":{"file_path":"/tmp/x.ts"}}' \
  | scripts/scope-gate-pretooluse.sh; echo "exit=$? (expect 2)"

# Allow: write a brief for the session, then retry
mkdir -p "${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}/briefs"
echo '{}' > "${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}/briefs/2026-06-15-SMOKE.json"
echo '{"session_id":"SMOKE","tool_input":{"file_path":"/tmp/x.ts"}}' \
  | scripts/scope-gate-pretooluse.sh; echo "exit=$? (expect 0)"
rm -f "${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}/briefs/2026-06-15-SMOKE.json"
```

Expected: first `exit=2`, second `exit=0`.

- [ ] **Step 4: Live registration test (non-destructive)**

```bash
cp ~/.claude/settings.json /tmp/settings.bak.json 2>/dev/null || true
scripts/scope-gate-register.sh
jq '.hooks | keys' ~/.claude/settings.json
jq '[.hooks.PreToolUse[].hooks[].command]' ~/.claude/settings.json
```
Expected: `PreToolUse` includes both `rtk hook claude` and `scope-gate-pretooluse.sh`; `UserPromptSubmit` includes `scope-gate-userpromptsubmit.sh`. Re-run `scope-gate-register.sh` and confirm no duplicates.

- [ ] **Step 5: Final commit (if any verification fixups were made)**

```bash
git add -A
git commit -m "scope-gate: verification fixups" || echo "nothing to commit"
```

---

## Self-Review

Run after the plan is written (checklist, not a dispatch):

1. **Spec coverage** — A (skill: Task 6), B (PreToolUse: Task 3), C (UserPromptSubmit: Task 4), D (settings registration: Task 5), E (brief schema + dir: Tasks 1, 6), F (harvester + tracker: Tasks 7, 8). Kill switch (lib + Task 3/5), measurement artifact (Task 6 schema + Task 7 reader), rung-scoping/retirement (Task 6 header + Task 8 tracker), error handling/fail-open (Task 3 + tests), three resolved decisions (granularity per-session: Task 3 brief-exists; noise floor: Task 2 `sg_is_floored_path`; autonomous mode: Task 6 step 5 + lib `sg_is_autonomous`). Open detail (per-env persistence): Task 5.
2. **Placeholder scan** — none; every step has concrete code/commands.
3. **Type/name consistency** — `sg_*` function names, `$AGENT_MATURITY_DATA_DIR`, `briefs/<YYYY-MM-DD>-<session_id>.json`, and `scope-gate-*.sh` paths used identically across lib, hooks, register helper, skill, and tests.
