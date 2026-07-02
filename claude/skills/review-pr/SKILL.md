---
name: review-pr
description: Review another person's PR against Yanxi's engineering standards and draft feedback in Yanxi's review voice. Use only when explicitly invoked (e.g. "/review-pr", "review this PR", given a PR link to review). Read-only on the author's branch — drafts comments for Yanxi to post, never posts as Yanxi.
disable-model-invocation: true
---

# Review PR

Review someone else's PR the way Yanxi would: judge the substance against the authoring guide,
phrase the feedback in Yanxi's review voice, and hand back draft comments. This is the reviewing
counterpart to `simplify-pr` (which fixes up Yanxi's *own* PRs) — both read the same canonical
guide, so the bar is identical on both sides.

This skill **drafts** a review. It does not post on Yanxi's behalf — leaving GitHub comments as
though they came from Yanxi is his call, not the agent's.

## Resolve the target

The user may pass a PR (URL or number) or nothing.

1. Explicit PR URL/number → use it.
2. Nothing, but on a branch with an open PR that *isn't* the user's own → ask which PR; don't
   assume. (Reviewing usually means a PR you're not the author of.)

Then gather what you need to judge it:

- The diff: `gh pr diff <n>`.
- Description + commits: `gh pr view <n> --json title,body,commits,author,url`.
- Existing review threads: `gh api repos/{owner}/{repo}/pulls/<n>/comments` and `.../reviews`, so
  you don't repeat a point someone already made.

## The two guides — read them, don't reproduce from memory

Both are the single source of truth and may have changed since this skill was written:

- **Substance** (what to flag): `~/dotfiles/claude/pr-authoring.md`
- **Voice** (how to phrase it): `~/dotfiles/claude/review-tone.md`
- **Worked examples** (calibration for what good looks like): `~/dotfiles/claude/pr-examples.md` —
  use these to judge whether a description is at the right altitude before flagging it as too long.

(If those paths don't resolve, fall back relative to this file: `../../pr-authoring.md`,
`../../review-tone.md`, and `../../pr-examples.md`.)

Apply the authoring guide as the review bar — the same things it tells an author to do are the
things you check for here. **The default stance is minimal:** comments, tests, and description
lines are additions that must earn their place, not defaults — flag anything present for its own
sake (a comment restating the code, a coverage-theater test, a description narrating the diff) as
removable, the way `simplify-pr` would. Then the specific areas:

- **Code** — `any`/`as`/`!` escape hatches, unvalidated boundaries, throwing where a discriminated
  result fits, auth bolted onto the caller instead of the service, premature abstraction or
  micro-optimization, observability with no consumer, swallowed errors.
- **Comments** — restating the *what*, change-narration, stale or AI-filler comments. Flag missing
  *why* on genuinely non-obvious code too.
- **Tests** — the high-sloppiness area: coverage-theater (tests of libraries, trivial mappings,
  thin control flow), and complex/over-mocked tests that signal the code needs dependency injection.
- **The PR description itself** — if it narrates the diff, buries the motivation, or leaves empty
  template sections, that's reviewable. A PR is a communication tool.

Then phrase every comment in Yanxi's voice per `review-tone.md`: concise, questions over commands,
curious not prescriptive, `lgtm` lowercase, no empty praise or formal filler.

## Output

1. A short **overall take** (1-3 sentences): is it close, or are there real concerns?
2. **Draft inline comments**, grouped by severity (blocking / nit), each as `file:line` → the
   comment text exactly as it would be posted (already in Yanxi's voice). Keep them few and
   high-signal — don't manufacture nits to look thorough.
3. Don't restate the diff back to the user; only surface what's worth a comment.

Then stop. Posting is the user's decision:

- Default: hand over the drafted comments for the user to post themselves.
- Only if the user *explicitly* says to post, and the repo's own rules allow an agent to (some
  repos — e.g. Vanta's — forbid posting review comments as a human; respect that), use
  `gh pr review` / `gh api`. Never approve, never request-changes as a gate, never promote or merge.

If the repo has its own review playbook (e.g. `.ai-rules/code-review/`), follow it for the checklist
and read-only constraints; this skill adds Yanxi's substance bar and voice on top, it doesn't override it.
