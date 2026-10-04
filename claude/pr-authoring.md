# Yanxi's PR Style

The shared standard for authoring and reviewing feature code, unit tests, comments, and PR
descriptions, whether or not a PR exists. Follow repository conventions and required templates;
this guide adds personal style, not a replacement for correctness or security requirements.

**Default to no.** Start with the smallest solution to the approved use case. Every addition
must earn its place: what necessary behavior or information would be lost if it were removed?
Being defensible, already written, or potentially useful is not enough. Prefer a materially
smaller approach when it meets the same requirements; trimming a few lines is not a substitute.
Nothing extra is a valid outcome.

Write for readers who never saw the conversation. Describe the final outcome and enduring
rationale, not rejected proposals, user corrections, or mistakes we introduced and then undid.

## 1. Feature code

Default to the smallest implementation, with no extra abstraction or refactoring. Add one only
when the actual use case needs it. Do not clean up unrelated code merely because it could be
"better."

## 2. Unit tests

Default to no new tests unless they protect a concrete behavior or failure not already covered.
Do not test for coverage, recheck a library or mock, or duplicate scenarios and assertions.
No new tests can be the right answer; do not delete meaningful protection just to lower the count.
Test the final contract, not our drafting history or the absence of a rejected, unshipped feature.

## 3. PR description

Default to `TIN` when the title and diff already tell the story. Do not add a summary merely
because a description field exists. Add prose only for necessary intent, decisions, or caller
impact the title and code cannot explain. Accuracy alone does not earn a sentence its place.
Stay high-level; never mechanically list files or changes. Preserve required template sections,
but keep their content minimal.
Do not repeat information already carried by the title, diff, or another section.
When tightening an existing description, fix concrete violations and leave compliant prose alone.

## 4. Comments

Default to no comments when the code is clear. Add one only for a necessary, non-obvious reason
or constraint the code cannot express. Do not restate names, types, or steps. Explain the final
behavior and enduring constraints; do not move private iteration history from comments into the PR.
Length follows the explanation's need, not a quota.

## 5. PR testing section

Default to no routine-check list. Do not mention ordinary unit tests, lint, typecheck, or CI
checks the reviewer already expects.
Report only verification the reviewer cannot see from CI, with what ran, its observed result, and
evidence. A short result plus a link or attachment to the full receipt is enough; keep distinct
checks, commands, setup, and cleanup there rather than listing every scenario in the body.
Use links or images when helpful; command output can be sufficient. Never invent evidence or turn
a unit test or drafting incident into a claim of manual verification. Cut private iteration history;
do not salvage it by rephrasing it as something we verified.

Name the actual test setup. Omit lists of services not exercised and limitations already clear from
that setup. State only a specific material gap the evidence would otherwise hide. If the template
requires an answer and no additional runtime verification exists, say so briefly. Keep internal
grading and review ceremony out of the description.

Before handoff, check the changed work against these five rules and fix concrete violations.
