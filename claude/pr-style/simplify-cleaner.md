# Simplify Cleaner (pre-handoff pass)

Run on a diff (or the changed files) before handing a PR off. The feature code is usually fine -
your job is the **comments, tests, and PR description** that came in messy. Read `rubric.md`
(Simplify section) and `../pr-authoring.md` (Code Comments, Tests, PR Descriptions) first.

Go target by target. For each candidate, output: the location, the rule it violates, the verdict
(CUT / TIGHTEN / KEEP), and - for TIGHTEN - the replacement.

## Comments
For every comment/JSDoc in the diff, ask in order:
1. Does the code already say this (restates the *what*, re-says a name)? -> CUT.
2. Will it be false after the next change (narrates "we used to / now / blocked... in INC-xxxx")?
   -> CUT or rewrite to evergreen present tense; move the incident/why-now to the PR.
3. Does it enumerate cases when one load-bearing *why* would do? -> TIGHTEN to the why.
4. Is it a genuine non-obvious why / gotcha / external-quirk? -> KEEP.

## Tests
For every new test, ask:
1. Does it only re-verify a library, an SDK call, or a static mapping - no Vanta logic? -> CUT.
2. Does it assert two implementations/libraries produce the SAME output (parity, equivalence,
   snapshot-vs-reference)? -> CUT. It feels like a migration safety guard, but the no-op is proven
   by the code; the test just pins two libraries together and exercises no Vanta logic. Do not
   rationalize it as an invariant worth guarding - this is the most common thing to wrongly keep.
3. Does it mock half the world / need `as any`/`as never` to build the unit? -> flag the *code*:
   the unit needs its deps injected. Don't paper over with more mocks.
4. Otherwise -> KEEP.
"Better than nothing" is not the bar. Deleting a false-coverage test is a win, not a loss.

## JSDoc (a comment sub-case the cleaner tends to under-cut)
- Per-field / per-param doc that restates the name or type -> CUT (`/** the output name */` on
  `outputName`).
- Multi-sentence doc -> TIGHTEN to one line unless every sentence carries a distinct non-obvious why.
- Keep a field/param doc only for a genuine non-obvious constraint. A self-describing name gets none.

## PR description
1. Does any part narrate the diff file-by-file? -> CUT to the shape (before -> problem -> after).
2. Formula opener ("One behavior change a reviewer can't see from the diff:")? -> rewrite plainly.
3. Testing section restating table stakes (unit tests / lint / typecheck)? -> CUT to the one
   non-obvious thing you actually verified, or one line.
4. Em-dash / colon pile-up in a paragraph? -> split.

## Output
A ranked list (highest-leverage cut first), then a one-line summary: "N cuts, M tightens". If it's
already clean, say so - don't manufacture edits. Default to CUT when unsure: the bar is "does a
reader need this after the next change lands?"
