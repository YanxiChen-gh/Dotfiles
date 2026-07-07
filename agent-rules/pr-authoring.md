# Code & PR Authoring

When writing code, code comments, or PR descriptions, follow the guide at `~/dotfiles/claude/pr-authoring.md` (worked examples in `pr-examples.md`).

Key points:
- Optimize for the reader's time; let effort scale with risk.
- Code: no `any`/`as`/`!` (except `as const`) - model the type instead. Validate untyped boundaries with Zod. Prefer discriminated results over throwing for control flow. Guard clauses, happy path last. Put auth in the service, not the caller. Don't abstract early or micro-optimize cached paths. Every log/metric needs a consumer and an action; never swallow errors silently.
- Comments and tests are where sloppiness hides - hold them to the same bar as code, not nice-to-haves.
- Comments: prefer self-documenting code; comment only the non-obvious *why* (a load-bearing comment can be long); delete restating/stale/AI-filler comments.
- One home for each fact: evergreen rationale lives in the code, change-context and the why-now in the PR - don't say the same thing in both.
- Tests: don't test for coverage's sake - no tests of libraries, trivial mappings, or thin control flow. A complex or heavily-mocked test is a red flag at the code or the test; inject deps instead of `as never`/`as any`. Keep tests flat and behavioral.
- Descriptions are concise and high-level: before → problem → after, no diff narration. Scale to the change and trust the diff - for a simple change the whole Changes section is often one line ("refactor X to Y so that Z") or TIN; spend words only on what the diff can't show. Use a decision table for remove/replace/migrate; delete inapplicable template sections rather than leaving them empty.
- Motivation is one or two sentences stating the root cause/tradeoff. Testing shows only the hard stuff as evidence (e2e, manual, reproducible command); skip the obvious. Deployment states blast radius when it matters.
- Sound like a person, not AI: vary sentence length and break up run-ons, plain words over exhaustive jargon, no formula openers ("One behavior change a reviewer can't see…"), go easy on em-dashes/colons.

<!--claude-only-->
**Comment self-check before handoff** - current models over-comment, so act on the guide's comment bar, don't just cite it: after writing, re-read every comment and test you added and delete any that narrate the change, restate the code, are obvious from the name, or only re-verify a type/mapping; keep only the non-obvious *why*. (A `comment-self-check.sh` PostToolUse hook also nudges this; retire this note when models stop over-commenting - the agent-maturity `verbose-output` tag.)
<!--/claude-only-->

