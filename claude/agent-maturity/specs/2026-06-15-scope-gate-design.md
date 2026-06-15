# Scope Gate — Design

_Spec date: 2026-06-15. Status: approved for planning._

A pre-execution intent/scoping gate for AI dev agents. The first **measured, removable,
rung-scoped** intervention in the agent-maturity system — built to move one metric and to
be retired when it stops earning its place.

## Why

`/maturity-review` (2026-06-15 baseline) scored the dev agent L2/L2/L2, weakest = **Spec**.
The dominant intervention is **clarification at 1.7/PR** (17 of 28) — heavy scope
redirection ("split this PR", "make it polymorphic", "stick with S3", dropdown-not-free-text)
that lands *after* the agent has already committed to an approach. Agents already self-initiate
~2.4 questions/PR, so the gap is **timing, not content**: scoping happens reactively mid-task
instead of up front.

**Goal:** force scoping *before* code on non-trivial tasks, to cut clarifications/PR.

**Success criterion:** the next `/maturity-review` reports clarifications/PR **below 1.7**
with agent-question precision holding (Ask-F1 not degraded) — a real before/after number,
not another `metric impact: TBD`. Moving that number is the gate's first job; being the first
intervention the system actually *measures and can ablate* is its second.

## Design principle: the gap is timing, not content

The three behaviors we want — (1) restate task + pass-to-pass acceptance checks,
(2) propose PR-decomposition when multi-part, (3) batch genuine scope questions up front —
are mostly **content the system already owns**: `superpowers:brainstorming` does
restate-and-clarify-upfront, `writing-plans` does decomposition. What is missing is a
**reliable trigger that fires before the first line of code** on non-trivial tasks. So this
design invests in the *trigger and the measurement*, and reuses existing skills for depth.

This rules out a pure auto-invoked skill on its own merits: model-invocation-by-description
is exactly the mechanism that fails today (agents don't reliably self-trigger scoping). The
**trigger must be deterministic** → a hook.

## Architecture: hooks enforce a recorded decision; the model supplies the judgment

A hook is deterministic code with no semantic judgment. It cannot read a task and decide
"non-trivial". So it does not try to. The model judges triviality; the hook's load-bearing
job is to force that judgment to be **explicit and recorded before code**, killing the
*silent skip* that is the actual failure mode.

Two halves:

- **Soft half — `UserPromptSubmit` hook.** Injects the triage rubric + a "re-run the gate on
  a new non-trivial task" directive, so compliance is usually voluntary.
- **Hard half — `PreToolUse(Edit|Write)` hook.** The backstop. Blocks the first code edit
  when no scoping decision is recorded for the session. This is the determinism that makes
  the gate mandatory; the soft half just makes the hard half rarely fire.

### Why not a heuristic threshold in the hook

The costly clarifications are **approach/semantic** scope, which correlates ~zero with diff
size: "make it polymorphic" can be a 15-line single-file change (a size gate waves it
through — false negative on the expensive case), while a 600-line mechanical rename is
trivial scope (a size gate blocks it — false positive). Keyword-matching the prompt is just
as weak. Any cheap proxy the hook could compute is poorly correlated with the pain, so the
hook does **not** gate on size or keywords. It gates on *"has a decision been recorded"*.

## Triage rubric (model-judged, injected by the soft hook)

> **Non-trivial (gate required)** if *any*: there is an approach/design choice; it adds or
> changes a public interface / type / endpoint / schema; it spans multiple files or systems;
> it is a "make it X"-shaped architectural ask; the work is multi-part (PR-decomposition
> candidate); or **you are unsure.**
> **Trivial (proceed)**: one obvious change, no new interface, no approach fork, cheaply
> reversible.
> **Default to non-trivial when unsure** — a skipped scope costs a ~1.7-clarification
> redirect; an unnecessary ~30-second brief costs almost nothing. The asymmetry says
> over-gate.

## Components

### A. `scope-gate` skill — `claude/skills/scope-gate/SKILL.md`

The *content*. When invoked (by the agent after self-classifying non-trivial, or because the
hard hook blocked an edit), it produces the brief:

1. Restate the task + **pass-to-pass acceptance checks**.
2. Propose a **PR-decomposition** if the work is multi-part.
3. **Batch genuine scope questions** up front.
4. Approval (mode-dependent — see below).
5. Write the brief artifact (E) and trigger a sync.

Delegates depth to `superpowers:brainstorming` / `writing-plans` rather than re-implementing
them. Header declares it a **Spec L2→L3/L4 lever** with the retirement trigger (see
"Rung-scoping").

Invocation: NOT `disable-model-invocation` (unlike `/maturity-review` and
`/harvest-interventions`, which are explicit-only) — this skill is *meant* to be invoked by
the agent mid-task, and the hard hook references it by name when it blocks.

### B. `PreToolUse(Edit|Write)` hook — `scripts/scope-gate-pretooluse.sh`

Deterministic backstop. Reads the hook JSON from stdin (`session_id`, `tool_name`,
`tool_input.file_path`). Decision order:

```
1. SCOPE_GATE=off?                          → allow (kill switch, line one)
2. file_path matches floor allowlist?       → allow + log floored edit
3. brief E exists for session_id
     AND triage covers this edit?           → allow
4. brief store unreadable (error)?          → allow + log (fail OPEN)
5. otherwise                                → BLOCK (exit 2) with message:
   "Scoping gate: no scoping decision recorded for this task. Before editing code,
    run /scope-gate (restate + acceptance checks + PR-decomposition + batched questions),
    or if genuinely trivial record it via the skill's --trivial path. Then retry the edit."
```

"Covers this edit" in v1 = a brief exists for the session at all (per-session granularity;
see Decisions). File-scope binding is a logged future tightening.

### C. `UserPromptSubmit` hook — `scripts/scope-gate-userpromptsubmit.sh`

Soft half. On each prompt, if `SCOPE_GATE != off`, emits the triage rubric + the directive:
"If this prompt starts a new non-trivial task distinct from the active brief, run
`/scope-gate` before editing code." Cheap, no blocking, no dependency on the private repo.

### D. settings.json registration + kill switch

Registers B and C in `~/.claude/settings.json`. `SCOPE_GATE=off` short-circuits both on line
one — the **one-line kill switch** (property 1). How this persists into fresh ephemeral Ona
envs is the one detail the implementation plan must pin down (see Open implementation detail).

### E. Brief artifact — `~/.agent-maturity-data/briefs/<date>-<session_id>.json`

The measurement substrate (property 2) AND the marker the hard hook checks. Lives in the
PRIVATE data repo (briefs reference internal task detail, like interventions), auto-synced by
`sync-maturity-data.sh` (`git add -A` already picks up new paths). Schema:

```json
{
  "session_id": "...",
  "created_at": "ISO-8601",
  "mode": "interactive | autonomous",
  "task_descriptor": "one line",
  "triage": "non-trivial | trivial",
  "trivial_reason": "string, present iff triage==trivial",
  "acceptance_checks": ["pass-to-pass check", "..."],
  "pr_decomposition": ["part 1", "..."],
  "questions": [
    {"q": "...", "resolution": "answered | assumed", "assumption": "string if assumed"}
  ],
  "covers": ["path or glob the brief scopes"]
}
```

`ensure-maturity-data.sh` gains a `mkdir -p "$DATA/briefs"` so the dir exists; no symlink
needed (the skill and hook reference `$AGENT_MATURITY_DATA_DIR/briefs` directly).

**Deadlock avoidance (load-bearing):** the skill writes the brief via the `Write` tool, which
is itself a `PreToolUse(Edit|Write)` event — with no brief yet, the hook would block the very
write that creates the brief. The floor allowlist covering `.agent-maturity-data` paths (step
2 in B, before the brief-existence check in step 3) is what prevents this; it is not just
noise-reduction.

### F. Harvester + tracker wiring — closes the ablation loop

`/harvest-interventions` gains a step that reads `briefs/` over the window to compute:

- **scoped-before-code rate** = non-trivial briefs produced before first edit ÷ non-trivial tasks.
- **Ask-F1 inputs** — batched up-front questions (from briefs) vs. clarifications that still
  landed later (from transcripts): rising precision + falling later-clarifications = the win.

`/maturity-review` reports these and runs the ablation check against this changelog entry.

**Measurement caveat (folds in the trailer correction):** the harvester's source B leans on
the `Co-Authored-By: Claude` trailer to tell agent commits from human ones. If all PRs are
treated as AI-generated, that signal is unreliable and the north-star denominator collapses
to "merged PRs". The brief artifact (E) becomes the more reliable per-task agent-authorship
signal. Reconcile in the harvester/rubric as part of F; full rework tracked separately.

## Resolved decisions

- **Granularity:** per-session brief carrying a `task_descriptor`; the model re-arms by
  re-running the gate on a new non-trivial task (driven by C's directive). The hard hook
  cannot detect task boundaries, so it does not pretend to. Most work here is one task per
  Ona job, so session≈task is a fine first approximation. *Future tightening (logged):* bind
  the brief to its `covers` paths and re-gate on edits outside that scope — also catches
  scope-creep — added only if harvested data shows multi-task-per-session leakage.

- **Noise floor:** a narrow allowlist of **cheap-to-be-wrong** paths — `*.md` / docs, the
  scope-gate's own brief/marker files, and `.agent-maturity-data` files — auto-allowed with
  no tag and **logged**. Never size-based, never general code (a 15-line code edit is where
  "should've been polymorphic" hides). The floor is kill-switchable; logging it means a
  floored path that later precedes a correction shows up as "floor too wide".

- **Autonomous mode:** two-phase. **Phase 1 (produce the brief) is hard-required in both
  modes** — the block is on the brief existing, never on human sign-off, so background jobs
  still produce the artifact and the measurement. **Phase 2 (approval):** interactive →
  synchronous human approval before code; autonomous → self-approve and proceed, with the
  batched questions recorded as explicit **assumptions** in the brief AND surfaced in the PR
  description for async human review at PR time. Mode detected via `$CLAUDE_JOB_DIR` (present
  in background jobs); default to autonomous-safe (never wait on input that won't come).

## Error handling — what keeps the gate from getting ripped out

- Hook errors / malformed stdin → **fail OPEN (allow), log.** A buggy gate must never wedge
  editing.
- Brief store unreadable (gh unauthed, repo absent) → **fail OPEN, log.** Distinguish
  *readable-but-no-brief* (legitimate block) from *unreadable* (fail open). Cost of a broken
  env is a missed gate, never a stuck session.
- Kill switch (`SCOPE_GATE=off`) and fail-open are the manual and automatic versions of the
  same safety promise.

## Rung-scoping / retirement (property 3)

The skill + brief header declare this a **Spec L2→L3/L4 lever**. Written retirement trigger,
recorded in `tracker.md`: *retire when agent-initiated scope-question precision is high AND
clarifications/PR is flat → the gate is no longer load-bearing.* The gate is built to be
deleted; the ablation check in `/maturity-review` is what will tell you when.

## Testing

- **Hooks (bash):** fixture-driven stdin JSON — (a) trivial/floor path allows, (b)
  code-edit-without-brief blocks (exit 2), (c) code-edit-with-valid-brief allows, (d)
  `SCOPE_GATE=off` allows, (e) autonomous detection via `$CLAUDE_JOB_DIR`, (f) malformed
  input and unreadable store both fail OPEN.
- **Brief schema:** validated; harvester parsing tested against sample briefs.
- **Skill:** a prompt — verified by the artifacts it produces conforming to the schema.

## Extraction-readiness (not built now; logged follow-up)

Build with no dotfiles-specific path assumptions and a skill/hook/script layout that maps
1:1 onto a Claude Code **plugin** structure, so the eventual extraction (which also retires
the per-env hook-install problem via `enabledPlugins`) is `git mv` + re-register, not a
rewrite. Tracked follow-up: extract the framework into a plugin after the gate has one
measured review cycle.

## Fresh-env persistence (resolved)

`install.sh` runs per-env and is the persistence path: `setup_scope_gate()` registers both
hooks in `~/.claude/settings.json` (idempotent merge) and eagerly creates
`~/.agent-maturity-data/briefs` so the PreToolUse hook hard-blocks from task #1;
`setup_claude_config()` symlinks the skill. Because the hook's logging (and that eager dir)
create `$DATA` before any maturity skill runs, `ensure-maturity-data.sh` provisions by
cloning the private repo *into* a pre-existing dir (init + fetch + checkout), preserving
untracked locals — a plain clone would fail on the non-empty dir. If provisioning fails
(gh unauthed), the skill still writes the brief locally so the now-always-active gate is
satisfied and work isn't wedged; it syncs on a later run.

## Where this lives

Dotfiles repo, branch `YanxiChen-gh/scope-gate` (off `main`, which already contains the
framework). Components A–F across `claude/skills/scope-gate/`, `scripts/`, and the private
data repo. This spec: `claude/agent-maturity/specs/2026-06-15-scope-gate-design.md`.
