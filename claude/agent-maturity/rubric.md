# Agent Autonomy Maturity Rubric

Canonical definition of the maturity model. The `/maturity-review` skill reads this to
score the current state — **don't reproduce it from memory**, edit it here.

## What this measures

The goal of the whole journey is **reducing human attention per shipped change**. So we
measure *outcomes* (attention spent), never *inventory* (tools owned). Owning eval infra
is L2-*capable*; eval infra that actually **gates merges** is L2-*achieved*. Always score
on "is the capability load-bearing in the real loop?", not "does it exist somewhere?".

Three dimensions, each scored L1–L5. They map to the three places attention goes:

| Dimension | The question | Maps to intervention type |
|---|---|---|
| **Trust** | How much do I review/correct agent output before merge? | `correction` |
| **Spec** | How much do I decompose/clarify before an agent can start? | `clarification` |
| **Babysit** | How much do I unblock/coordinate while agents run? | `unblock` |

**Overall level = the weakest dimension** (min). You are only as autonomous as your
weakest layer — a perfect verifier doesn't help if agents stall hourly waiting on you.

### Vocabulary alignment (so the rubric is legible to others)

Our 3-axis decomposition is our own, but the levels map onto the published models — cite
these when sharing, and borrow their language rather than inventing parallel terms:

- **Overall progression ≈ [Swarmia's single axis](https://www.swarmia.com/blog/five-levels-ai-agent-autonomy/)** "how much work before returning for feedback": L1 Assistive → L2 Conversational → L3 Task Agent → L4 Autonomous Teammate → L5 Agentic Avalanche.
- **Our dimensions ≈ [Augment's 8-dimension AI-SDLC model](https://www.augmentcode.com/guides/ai-sdlc-maturity-model)**: Trust ≈ their *review model* + *human roles*; Spec ≈ *agent autonomy* + *SDLC coverage*; Babysit ≈ *integration point* + *orchestration*. Their stages (Adopt → Embed → Coordinate → Orchestrate) are roughly our L2 → L3 → L4 → L5.
- This is alignment, not adoption — both of those are single-axis or org-level, so we keep our own per-person evidence-based scoring.

## North-star metric

**Interventions per merged agent-PR** = (corrections + clarifications + unblocks) ÷ merged
agent-authored PRs, over a window. Trend it down. Sourced from `interventions.jsonl` plus
GitHub PR history. Per-dimension rate isolates *which* layer is costing you.

### Supporting signals (borrowed from [Anthropic's autonomy measurement](https://www.anthropic.com/research/measuring-agent-autonomy))

Anthropic tracks these internally for Claude Code; they're the closest validated analogue to
this system and directly proxy two of our dimensions. Add them once the data exists:

- **Agent-initiated pause / question rate** — how often the agent *itself* stops to ask
  before guessing. A **Spec** proxy and a direct read on Ask-F1: rising (with good precision)
  means the agent is self-scoping rather than barreling into wrong assumptions.
- **Human-interruption rate** — fraction of agent runtime where *you* had to step in
  unprompted. A **Babysit** proxy. Anthropic saw interventions/session fall 5.4 → 3.3 over a
  quarter; that "interventions per unit of work, trended down" shape is exactly our north star.

---

## Trust — review & correction burden

| Level | You are here if… | Evidence |
|---|---|---|
| **L1 Supervised** | You read every diff line-by-line; you frequently rewrite agent logic before merge. | High correction rate; many post-handoff force-pushes; multiple review round-trips. |
| **L2 Self-checked** | Agent runs tests/typecheck/lint before handoff. You still read most diffs but rarely rewrite logic. Verification is *available* but doesn't hard-block "done". | Correction rate dropping; agent rarely hands off red. |
| **L3 Self-verified + judged** | Agent self-verifies **end-to-end** (exercises the *running* app, not just unit tests) AND a **separate evaluator/review agent** gates the diff before you see it. You spot-check. | `full-verification-workflow` is the default; `review-pr` runs before your eyes; verification *gates* completion. |
| **L4 Auto-reviewed** | Adversarial review runs automatically on every commit/agent-task. You review only flagged exceptions. Correction rate < ~10%. | Review is no-manual-trigger; flagged-only queue; low correction rate sustained. |
| **L5 Trusted by default** | You audit by sampling. PRs ship with an evidence bundle a human *could* check but usually doesn't need to. | Sampling-only review; evidence bundles standard. |

## Spec — task setup burden

| Level | You are here if… | Evidence |
|---|---|---|
| **L1 Hand-fed** | You write detailed prompts and decompose every task by hand; under-specified tasks go wrong. | High rework rate; long prompt-writing time; agents guess and miss. |
| **L2 Context-primed** | Reusable context (AGENTS.md / CLAUDE.md / skills) lets agents start with less hand-holding, but you still decompose the work. | Stable AGENTS.md/skills; fewer "you forgot X" corrections. |
| **L3 Spec-as-tests** | Agent converts the spec into **executable graders (pass-to-pass tests)** as step one, and plans-then-executes so ambiguity surfaces before code. | Tests-first artifacts on tasks; plan step catches misreads pre-code. |
| **L4 Self-scoping** | A **detector/intent agent** gates "do I have enough to proceed?" and batches the *right* questions at the *right* time (good Ask-F1 — neither silent-guessing nor question-spam). | Low rework rate; questions land before wrong turns, not after; rising *agent-initiated question rate* at good precision. |
| **L5 Intent-driven** | You hand high-level intent; the agent scopes, decomposes, and asks only genuinely-needed questions itself. | Minimal pre-writing; you state outcomes, not steps. |

> **Ask-F1** (the Spec quality metric): harmonic mean of question *precision* (relevant Qs ÷ asked)
> and *recall* (real blockers addressed ÷ total blockers). Penalizes both under-asking and
> spam. The L3→L4 move is the single strongest measured lever on autonomy in the research.

## Babysit — orchestration burden

| Level | You are here if… | Evidence |
|---|---|---|
| **L1 Hand-held** | You kick off each step, resolve conflicts, unblock constantly; agents lose state at context limits. | High unblock rate; frequent context-loss restarts. |
| **L2 State-externalized** | Progress log + feature-list JSON + git let agents resume on fresh context; worktrees isolate work. | Agents resume from files, not from you; isolated worktrees. |
| **L3 Durable** | Agents run unattended for long stretches; a durable session/event log lets a crashed agent reboot and resume; sub-agents work in clean contexts. | Long unattended runtime; low *human-interruption rate*; self-resume after crash; coordinator + sub-agents. |
| **L4 Decoupled fleet** | Brain decoupled from execution hands; one operator runs many concurrent agents; agents self-unblock common cases. | Many concurrent agents sustained; low unblock rate at scale. |
| **L5 Playbook fleet** | Front-loaded playbooks fan work across many tasks/repos; agents delegate to each other; you write instructions, not babysit. | Fleet runs from a playbook; attention = authoring instructions. |

---

## Scoring procedure (for `/maturity-review`)

1. For each dimension, pick the highest level whose criteria are **fully** met by evidence
   (not "we have the tool" — "the tool is load-bearing in the real loop").
2. Overall = min across dimensions.
3. Compute intervention rates (total + per type) over the window from `interventions.jsonl`
   and GitHub. State the trend vs the previous tracker entry. Where the data exists, also
   report the supporting signals (agent-initiated question rate → Spec; human-interruption
   rate → Babysit); if it doesn't yet, say so rather than guessing.
4. Recommend **exactly one** next move: the cheapest lever on the **weakest / most-painful**
   dimension. Prefer wiring up an asset that already exists over building new.
5. Ablation check: did the *previous* changelog change actually move the metric? If not,
   flag it as candidate scaffolding to remove (models improve; strip what's not load-bearing).

---

## Future revisits (deliberately not built yet)

Parked items — revisit when the trigger condition hits, not before. Logged here so they're
not silently forgotten.

- **Machine-maintained backend for the intervention log.** Today the log is a flat
  `interventions.jsonl` + manual/`/maturity-review` scoring — correct while volume is low.
  **Trigger to revisit:** the log outgrows a hand-managed file, or you want live trend
  dashboards instead of on-demand reviews. **Candidate:** self-hosted **Langfuse** (MIT) —
  log a `human_intervened` score + `pr_number` per trace and trend natively; **Helicone**
  (Apache-2) is the runner-up via custom properties. Caveat confirmed in research: *no* OSS
  tool does the autonomy *scoring* — adopting a backend only moves where the raw log lives,
  the rubric + meta-eval stay ours. So this is storage ergonomics, not a capability gap;
  don't adopt preemptively.

- **PR review-thread mining (the async post-handoff loop) — "source D".** Evidence retrieval
  today captures the in-session human↔agent loop (transcripts), git fixups, and only *coarse*
  PR review-cycle counts. It does NOT mine PR comment threads: reviewer/bot (Codex/automated)
  findings, the agent's resolution attempts, and who drove each fix. That loop is almost
  entirely a **Trust** signal, so the current Trust score is **systematically undercounted** —
  the real review burden is higher than the in-session correction rate suggests. **Trigger to
  revisit:** Trust becomes the weakest dimension, or you want a truer interventions/PR number.
  **How:** `gh pr view <n> --json reviews,reviewThreads,comments` + `gh api .../pulls/{n}/comments`.
  Two design notes: (1) **dedup** against in-session relays (a comment you then handed to the
  agent would double-count — reconcile by same-PR/same-day); (2) **classify by resolver** —
  bot-found-and-agent-fixed-autonomously is a *positive* Trust signal, human-had-to-step-in is
  the intervention. Deferred because Spec, not Trust, is the current bottleneck.
