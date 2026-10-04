---
name: review-pr
description: Review another person's PR using repository standards and Yanxi's canonical PR style, then draft feedback in Yanxi's review voice. Use only when explicitly invoked. Read-only on the author's branch; never posts as Yanxi.
disable-model-invocation: true
---

# Review PR

Review correctness against the repository's conventions and personal style against the two
guides below.

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

- **PR style**: `~/dotfiles/agent-rules/guides/pr-authoring.md`
- **Voice**: `~/dotfiles/agent-rules/guides/review-tone.md`

(If those paths don't resolve, fall back relative to this file: `../../../agent-rules/guides/pr-authoring.md`
and `../../../agent-rules/guides/review-tone.md`.)

Check the changed code, tests, comments, description, and verification evidence against all
applicable guide rules. For a style finding, name the rule and the affected span.

## Output

1. An **overall take**: is it close, or are there real concerns?
2. **Draft inline comments**, grouped by severity (blocking / nit), each as `file:line` → the
   comment text exactly as it would be posted.

Then stop. Posting is the user's decision:

- Default: hand over the drafted comments for the user to post themselves.
- Follow the global PR-comment confirmation rule: show the drafts and target PR, then wait for
  explicit user confirmation before posting. A review request alone does not authorize posting.
  Repository restrictions still apply (some repos forbid posting as a human). Only after
  confirmation, use `gh pr review` / `gh api` for the confirmed feedback. Never approve, never
  request-changes as a gate, never promote or merge.

If the repo has its own review playbook (e.g. `.ai-rules/code-review/`), follow it for the checklist
and read-only constraints; this skill adds Yanxi's PR style and review voice, not a replacement.
