# Yanxi's PR Style

The shared standard for authoring and reviewing feature code, unit tests, comments, and PR
descriptions, whether or not a PR exists. Follow repository conventions and required templates;
this guide adds personal style, not a replacement for correctness or security requirements.

**Default to no.** Extra code, refactoring, tests, comments, and prose must earn their place by
solving a concrete problem or carrying necessary information. "Good practice," completeness,
and looking thorough are not justifications. Nothing extra is a valid outcome.

## 1. Feature code

Default to the smallest implementation, with no extra abstraction or refactoring. Add one only
when the actual use case needs it. Do not clean up unrelated code merely because it could be
"better."

## 2. Unit tests

Default to no new tests unless they protect a concrete behavior or failure not already covered.
Do not test for coverage, recheck a library or mock, or duplicate scenarios and assertions.
No new tests can be the right answer; do not delete meaningful protection just to lower the count.

## 3. PR description

Default to `TIN` when the title and diff already tell the story. Do not add a summary merely
because a description field exists. Add prose only for necessary intent, decisions, or caller
impact the title and code cannot explain. Stay high-level; never mechanically list files or
changes. Preserve required template sections, but keep their content minimal.
When tightening an existing description, fix concrete violations and leave compliant prose alone.

## 4. Comments

Default to no comments when the code is clear. Add one only for a necessary, non-obvious reason
or constraint the code cannot express. Do not restate names, types, or steps. Keep lasting
rationale in code and change narration in the PR. Length follows the explanation's need, not a quota.

## 5. PR testing section

Default to no routine-check list. Do not mention ordinary unit tests, lint, typecheck, or CI
checks the reviewer already expects.
Report verification they cannot see from CI, such as local e2e, smoke tests, manual checks, or a
focused check of permissions, deployment targeting, or a failure path. Include evidence for each
claim: what ran and its observed result, with links or images when they help inspect the result.
Command output is sufficient when it proves the claim; do not manufacture screenshots or results.
Keep distinct checks and the setup needed to interpret them, rather than compressing them into
"verified end to end." If there is no additional runtime verification, say so briefly when the
template requires an answer. Keep internal grading and review ceremony out of the description.

Before handoff, check the changed work against these five rules and fix concrete violations.
