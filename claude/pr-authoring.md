# Yanxi's Code & PR Authoring Guide

How to write code, code comments, and PR descriptions on behalf of Yanxi. The throughline:
**optimize for the reader's time, and let effort scale with risk.** Say what someone needs to
understand the change and nothing the diff already says; spend words and care where a reviewer
or a future debugger actually needs them, and stay terse everywhere else.

The lens is backend TypeScript, but the principles are general. This sits *on top of* a repo's
own conventions and PR template - follow those, and apply this to fill the gaps. For worked
examples that calibrate altitude and voice, see `pr-examples.md` alongside this file.

## Writing the Code

- **No escape hatches.** Avoid `any`, `as` (except `as const`), and `!`. A cast usually means
  the design is wrong - fix the seam instead. Model the type with `satisfies`, discriminated
  unions, null checks, or optional chaining. In tests, casts like `as never` or undefined-returning
  mocks are the same smell: inject the dependency so the test can override it honestly.
- **Validate at the boundary.** Parse untyped input (`JSON.parse`, request bodies, third-party
  responses) with Zod `safeParse` and fail explicitly - don't cast trust into the system. Use
  assertion functions to narrow `unknown` from library callbacks rather than asserting with `as`.
- **Make illegal states unrepresentable.** Prefer tagged unions over boolean flags, and return a
  discriminated result (`{ ok: true, ... } | { ok: false, reason }`) over throwing for expected
  control flow. Reserve thrown errors for "should never happen."
- **Guard clauses, happy path last.** Return early for auth/validation/error cases so the main
  logic sits at the lowest indentation.
- **Put auth where it can't be skipped.** Authorization and audit logging belong *inside* the
  service/underlying API, not bolted onto each caller - so every consumer (resolver, REST route,
  agent tool, job) is protected by default. Selective or caller-side auth is a bug, not a shortcut.
- **Don't abstract early.** Inline a helper used in one place; factor out only genuine duplication.
  Don't micro-optimize paths that are already cached or dataloaded. Justify any cleverness - if it
  hurts readability without a strong reason, it's not worth it. Prefer the simplest deterministic
  version and ship incrementally.
- **Observe with intent.** Every log, metric, and monitor needs a consumer and an action - don't
  add one that duplicates what APM/Datadog/LangSmith already capture, and don't log in hot or shadow
  paths where it's just noise. Keep metric tags low-cardinality; high-cardinality IDs go to logs.
  **Never swallow errors in an empty `catch`** - failures should surface loudly so we can fix them
  (the rare deliberate swallow needs a comment saying why).
- **Prefer additive over mutating shared state.** Create a new template/key/version rather than
  editing a shared prod resource in place; it's cheaper to revert and harder to break.

## Code Comments

Comments and tests are where sloppiness hides. They get rushed as "nice-to-haves" after the real
work, and they rot faster than code - so hold them to the *same* bar as the code, or cut them.

**Prefer self-documenting code first.** Clear names and structure remove the need for most comments.
If good code can already say it, don't write a comment.

- **Comment the non-obvious *why*, never the *what*.** A comment earns its place only when the code
  genuinely can't carry the meaning: a gotcha, a workaround, a surprising data model, an external-
  library quirk, or a deliberate deviation from the house style (link the upstream source when the
  constraint is external). Restating what the code does is clutter. Length isn't the problem; value
  is. A ten-line note on a genuinely non-obvious data model earns its space. A one-liner restating an
  obvious assignment doesn't. If you're writing a long comment to explain confusing code, first ask
  whether the code should be clearer instead.
- **Comments must be evergreen.** True after the next change lands. Change-narration ("we used to do
  X", "this is now different because…", "Phase 0") and AI-generated step-by-step filler go stale
  immediately and clutter the read - strip them before handing off. That context belongs in the PR
  or an inline review note, not the code.
- **One home for each fact.** Evergreen rationale (why the code is shaped this way) lives in the
  code; change-context and the why-now live in the PR. Don't say the same thing in both. If a code
  comment already explains a design decision, the PR description shouldn't re-explain it - pick the
  right home and say it once.

Good comments look like: *"Use string keys - ObjectId instances don't compare by value"*,
*"http-proxy-middleware, not express-http-proxy, because the latter buffers the full body and would
break SSE streaming"*, *"domainId is logged below, not tagged on the metric, to keep cardinality
bounded"*. Each explains a decision you'd otherwise be tempted to "simplify" into a bug.

## Tests

Same bar as comments: a test is real engineering, not a box to tick. Most sloppy tests fail one of
these two checks.

- **Don't test for the sake of it.** A test that only re-verifies a library (a Zod schema, an SDK
  call), a static mapping, thin control flow, or that only asserts an observability signal fired (a
  metric emitted, a log written) rather than exercising branch logic is *negative* value - it gives
  false coverage and drags CI. Test where the business logic actually is. ("Better than nothing?"
  is not the bar.) The same applies inside a test: an assertion that re-checks what another
  assertion already proves is noise - keep the one that pins the behavior, cut the rest.
- **A complex test is a red flag - at the code or the test.** If a test is hard to follow or mocks
  half the world, the signal usually points at the production code: the unit needs its dependencies
  injected so they can be overridden cleanly. Reaching for `as never` / `as any` to build the
  unit under test means you're not building it correctly. Aim for flat, behavioral tests - real
  fixtures, descriptive names, small assertion clusters.
- **Verify what units can't prove.** For agent/runtime/integration code, typecheck and unit tests
  aren't enough - run it end to end and confirm before merge.

## PR Descriptions

Concise and high-level. Describe the *shape* of the change, not a line-by-line tour.

- **Frame it as before → problem → after.** What the world looked like, what was wrong with it, and
  what it looks like now - all at high altitude. Describe intent and outcome, not mechanics.
- **Don't narrate the diff.** The reviewer can read what each file does. Name the load-bearing
  symbols/packages if it helps orient them, but don't walk through the change file by file.
- **Scale to the change, and trust the diff.** Most of what a small change does is readable from
  the diff, so don't re-narrate it. For a simple or mechanical change the whole `## Changes` section
  is often *one* high-level line: "Refactor X to Y so that Z", "Remove the unused `userId` field
  from `ToolContext`", or even just `TIN` when the title and diff say it all. Spend words only on
  what the diff *can't* show, like a subtle behavior change or a non-obvious reason. The mechanics
  that are right there in the code (the data structures, the duplication you removed, the helper you
  added) are noise in the description. A risky migration earns per-file guidance and links; a small
  refactor doesn't. When in doubt, write less and let Motivation carry the why.
- **For remove / replace / migrate PRs, use a decision table.** One row per item: what happened to
  it, what replaced it, and why. It's the clearest possible before→after.
- **Fill the template, delete what doesn't apply.** Drop inapplicable sections rather than leaving
  empty placeholder comments - a half-filled template reads as "I didn't bother."

Example:
> Before, alarms were keyed by raw string IDs, so a renamed rule silently matched nothing.
> This makes keys structural so a rename is a type error instead of a silent miss.

### Sound like a person

The clearest sign of AI-written prose is that no person talks like that. Write the way you'd
explain the change to a teammate at your desk - this applies to the description, motivation, and
any review comment.

- **Vary sentence length; break up run-ons.** If one sentence has a colon, two clauses, and a dash
  all doing work, split it. People pause for breath.
- **Plain words over exhaustive precision.** "with an `eslint-disable` for the unsafe cast," not
  "behind `no-unsafe-type-assertion` escape hatches." Say it how you'd say it out loud.
- **No formula openers.** "One behavior change a reviewer can't see from the diff:" is template-
  shaped. "Worth flagging since the diff won't show it" carries the same thing without the scaffolding.
- **Go easy on em-dashes and colons.** A pile of them in one paragraph is the strongest tell - one
  per paragraph, tops.
- **A little informal is fine.** "basically a hand-rolled cache," "nothing changes for callers."
  Natural beats polished.

### Motivation

One or two sentences, stating the **root cause or the tradeoff** - not a restatement of the
description. Answer "why now / what was blocked." If a ticket is linked, still give the one-line
gist inline so the reviewer doesn't have to open it.

### Testing

Only call out what a reviewer can't safely assume.

- **Skip the obvious.** Unit tests, type checks, and lint are table stakes - CI proves them.
- **Show the hard stuff as evidence.** Name the failure modes a test covers, paste the reproducible
  command (with real output), or attach the screenshot. Say what you actually did so the reviewer
  doesn't re-do it. If there's genuinely nothing beyond the obvious, one short line is fine.

### Deployment

When it matters, state the **blast radius / revert impact** in a line, and link the feature flag
if the change is gated. "Safe, easy to roll back" is a complete answer when it's true.

### AI disclosure

Where a template asks how AI was used, make it a mini-ADR when design alternatives were weighed:
the model, and the key prompt plus the options considered and why you landed where you did. That
turns a compliance field into a useful record. Skip the ceremony when nothing was decided.
