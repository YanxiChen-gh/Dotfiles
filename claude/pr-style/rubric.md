# PR Style Rubric (Yanxi)

This is the **eval layer** for the PR flows, not the generation tool. Generation already lives
elsewhere: the `pr-authoring.md` guide (wired via CLAUDE.md + the pr-authoring-gate hook) and the
`simplify-pr` / `review-pr` skills. This file exists so the judge has something to score against;
it points at those guides and adds only checkable questions + contrastive pairs + anti-tells.

**The style specs (read these first, they are authoritative):**
- Authoring & code & comments: `../pr-authoring.md` (+ `../pr-examples.md`)
- Review voice: `../review-tone.md`

Three flows, each graded against the relevant guide.

## Authoring (grade against pr-authoring.md "PR Descriptions")

Signature moves (checkable):
- **before -> problem -> after** at high altitude, not a file-by-file tour.
- **Scales to the change**: a mechanical PR's `## Changes` is one line (or `TIN`); words spent only
  on what the diff can't show.
- **Sounds like a person**: varied sentence length, plain words, no formula openers, <=1 em-dash
  per paragraph.
- **Motivation states root cause / tradeoff**, not a restatement of the description.
- **Testing shows only the non-obvious** (repro command + real output, screenshot), skips "ran unit
  tests / lint".

Anti-tells (penalize):
- **Diff narration** - walking through each file the reviewer can already read.
- **Formula openers** - "One behavior change a reviewer can't see from the diff:", template scaffolding.
- **Em-dash / colon pile-up** in one paragraph (the strongest AI tell per the guide).
- **Half-filled template** with empty placeholder comments left in.
- **Testing section restating table stakes** ("added unit tests, ran lint, typecheck passes").

## Review (grade against review-tone.md)

Signature moves:
- **Questions over commands** ("Should this be X?" not "Change this to X").
- **Curious before prescriptive** - asks "why" / "Hmm" before demanding.
- **Challenges scope & approach**, not just code (PR-size pushback, build-vs-not).
- **Approvals are brief** - lowercase "lgtm", one line, or empty.
- **Ends with "What do you think?"** when raising a concern.

Anti-tells:
- **Empty praise** ("Great work!", "Nice job!").
- **Corporate hedging** ("I would like to suggest...", "Perhaps we could consider...").
- **Over-explaining** where a short question suffices; bullet lists for a one-line comment.
- **"LGTM" in caps**, or "Nit:" on something that isn't minor.

## Simplify (grade against pr-authoring.md "Code Comments" + "Tests" + "PR Descriptions")

This is the priority flow. The feature code is usually fine; the **comments, tests, and PR
description** come in messy and need cleaning before handoff. So "simplify" here means: find the
low-value comment/test/description cruft and cut or tighten it. Calibrated against real cleanup
diffs in the private data repo (`$STYLE_HARNESS_DATA/pr-style/corpus/simplify/human/cleanup-examples.md`).

What to flag, by target:

**Comments** (cut or tighten):
- Restates the *what* the code already says, or just re-says a name (`/** the output name */`).
- Not evergreen: narrates this change ("blocked... in INC-1234", "we used to", "now"), or carries
  a fact whose home is the PR (incident refs, why-now).
- Over-specific: enumerates every consumer/case when one load-bearing *why* would do.
- AI step-by-step filler.

**Tests** (delete):
- Only re-verifies a library, an SDK call, or a static mapping - no Vanta logic exercised.
- **Asserts two implementations/libraries produce the same output** (parity / equivalence /
  snapshot-vs-reference between two vendored libs). A migration being a no-op is proven by the
  code, not by a test that pins two libraries together. Delete it - the invariant guard feels
  valuable but exercises no Vanta logic. (Calibration miss #1: this is the one the cleaner keeps.)
- **Only asserts an observability signal fired** (a metric emitted, a log written) rather than
  exercising branch logic. Instrumentation plumbing, not Vanta logic - delete. Keep the test that
  covers the real branch (e.g. an abort/error-classification guard). (Held-out gap, ex6.)
- **Redundant assertion within a test** - re-checks what another assertion in the same test already
  proves (a `status === 200` next to a metric assertion that pins `statusClass: "2xx"`). Cut the
  redundant one; keep the assertion that pins the behavior. (Held-out gap, ex8.)
- Complex / mocks half the world - the smell points at the code (inject deps), not more mocking.

**PR description** (trim):
- Narrates the diff file-by-file; formula openers; a Testing section restating table stakes.

**Comments, specifically JSDoc** (the cleaner under-cuts these): delete every per-field or
per-param doc that just restates the field/param name or type (`/** the output name */` on
`outputName`). Collapse a multi-sentence doc to one line. Keep a field/param doc only for a
non-obvious constraint. Default: a self-describing name gets no doc.

Also, where it's right there: **don't abstract early** - inline a one-use helper, **even when it's
a type predicate**, unless the narrowed type is reused by more than one caller. A one-call
`x is Y` guard feeding a single `includes()` is inlineable. A cast/`!` means fix the seam, not
silence it.

Anti-tell: keeping a comment/test/section because deleting feels like losing coverage. Fewer lines
is not the goal; **less to understand and nothing that will rot** is. "Better than nothing" is not
the bar.

## Contrastive pairs

Seeded from `pr-authoring.md`'s own examples; grow this from real review catches.

| Flow | Anti-tell | Bad | Fix |
|---|---|---|---|
| Authoring | Formula opener | "One behavior change a reviewer can't see from the diff:" | "Worth flagging since the diff won't show it:" |
| Authoring | Diff narration | "In foo.ts we add a field; in bar.ts we update the caller; in baz.test.ts we..." | "Make alarm keys structural so a rename is a type error, not a silent miss." |
| Review | Empty praise + command | "Great work! Change this to use a Map." | "Hmm can you just use a Map here instead of overriding fields one by one?" |
| Review | Corporate hedge | "I would like to suggest we consider extracting this." | "the duplicated blocks might be worth extracting to avoid drift" |
