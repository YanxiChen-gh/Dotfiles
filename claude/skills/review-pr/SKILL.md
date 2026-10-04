---
name: review-pr
description: Review another person's PR using repository standards and Yanxi's canonical PR style, then draft feedback in Yanxi's review voice. Use only when explicitly invoked. Read-only on the author's branch; never posts as Yanxi.
disable-model-invocation: true
---

# Review PR

Review correctness against the repository's conventions and personal style against
`pr-authoring.md`, the same standard used by the author and `simplify-pr`. Return draft feedback
in Yanxi's review voice.

This skill **drafts** a review. It does not post on Yanxi's behalf - leaving GitHub comments as
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

## The two guides - read them, don't reproduce from memory

Both are the single source of truth and may have changed since this skill was written:

- **PR style** (the five shared rules): `~/dotfiles/claude/pr-authoring.md`
- **Voice** (how to phrase it): `~/dotfiles/claude/review-tone.md`

(If those paths don't resolve, fall back relative to this file: `../../pr-authoring.md`
and `../../review-tone.md`.)

Check the changed code, tests, comments, description, and verification evidence against all
applicable guide rules. For a style finding, name the rule and the affected span; do not invent
extra criteria or propose unrelated cleanup.
Use `review-tone.md` for the wording of outward-facing feedback.

## Output

1. A short **overall take** (1-3 sentences): is it close, or are there real concerns?
2. **Draft inline comments**, grouped by severity (blocking / nit), each as `file:line` → the
   comment text exactly as it would be posted (already in Yanxi's voice). Keep them few and
   high-signal - don't manufacture nits to look thorough.
3. Don't restate the diff back to the user; only surface what's worth a comment.

Then stop. Posting is the user's decision:

- Default: hand over the drafted comments for the user to post themselves.
- Follow the global PR-comment confirmation rule: show the drafts and target PR, then wait for
  explicit user confirmation before posting. A review request alone does not authorize posting.
  Repository restrictions still apply (some repos forbid posting as a human). Only after
  confirmation, use `gh pr review` / `gh api` for the confirmed feedback. Never approve, never
  request-changes as a gate, never promote or merge.

If the repo has its own review playbook (e.g. `.ai-rules/code-review/`), follow it for the checklist
and read-only constraints; this skill adds Yanxi's PR style and review voice, not a replacement.
