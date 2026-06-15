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

   This creates `$AGENT_MATURITY_DATA_DIR/briefs` even if provisioning fails. If it
   reports gh isn't authenticated / repo inaccessible, **do not stop** — warn the user
   that the brief won't sync until that's resolved, then still write the brief locally
   (step 6) so the gate is satisfied and work isn't wedged. It will sync on a later run.

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
