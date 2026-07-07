---
name: simplify-pr
description: Rewrite a PR description and clean up code comments to match Yanxi's PR authoring guide. Use only when explicitly invoked (e.g. "/simplify-pr", "simplify this PR", "tighten up the PR description") - typically when an agent produced a bloated, diff-narrating PR description or left change-context comments in the code.
disable-model-invocation: true
---

# Simplify PR

Take a PR that's grown bloated - a description that narrates the diff file-by-file,
restated motivation, padded testing notes, or code comments that explain *this change*
rather than the code - and tighten it to match Yanxi's authoring guide.

This is a manual cleanup tool. You're invoked because the CLAUDE.md authoring instruction
got ignored (an agent wrote the PR without it). So the bar is: leave the PR reading the way
it would have if the guide had been followed from the start.

## When invoked

The user may pass a PR (URL or number), or nothing. Resolve the target in this order:

1. An explicit PR URL/number in the request → use it.
2. Otherwise the open PR for the current branch: `gh pr view --json number,title,body,url`.
3. No PR yet (branch not pushed, or pre-PR) → work from the branch diff and draft a
   description the user can use when they open the PR. Say that's what you're doing.

Then gather the context you need to judge the description against reality:

- The actual diff: `gh pr diff <n>` (or `git diff main...HEAD` when there's no PR).
- The commits: `gh pr view <n> --json commits` or `git log main..HEAD`.
- The current description (from step 2/3 above).

You need the diff because the whole point of the guide is to say what the reviewer
*can't* already read from it. You can't apply that test without seeing the diff.

## The guide

Read the canonical authoring guide and apply it - **don't reproduce it from memory**, since
it's the single source of truth and may have changed:

    ~/dotfiles/claude/pr-authoring.md

(If that path doesn't resolve, fall back to `pr-authoring.md` two levels up from this skill -
`../../pr-authoring.md` relative to this file.)

Also read the worked examples alongside it - they calibrate *how short* to go and what the right
voice sounds like, which is the thing this skill most often overshoots:

    ~/dotfiles/claude/pr-examples.md

Match the **altitude** of the example closest in size/type to the PR you're tightening; don't copy
its words.

The guide covers the whole PR: a concise before → problem → after **description**, a short
**motivation**, **testing** notes that mention only the non-obvious, **evergreen code comments**,
and the code/tests themselves. For this cleanup skill, focus on the description and comments, but
also **flag** (don't rewrite) any test smells the guide calls out in the diff - coverage-theater
(tests of libraries or trivial mappings) and complex/over-mocked tests that should use dependency
injection. The operational points the guide can't know about, which this skill adds:

- **Be aggressive on comments - default to cutting, not flagging.** Current models (Opus 4.8)
  over-comment badly, and this skill's failure mode is leaving too much. For *every* added
  comment, the default is **remove** unless it carries a non-obvious *why* (gotcha, workaround,
  external-library quirk, surprising data model). Remove on sight: change-narration ("we used
  to…", "now X", "Phase 0"), restatements of what the code says, comments obvious from the
  symbol name, and step-by-step "first… then…" filler. Same for tests: a test that only
  re-verifies a library/type/static mapping is negative value - call it out for deletion, don't
  preserve it. When in doubt, cut it; the user would rather re-add a rare needed comment than
  hand-strip ten. _(This aggressiveness is tuned to today's verbose models; revisit on a model
  upgrade - see the agent-maturity `verbose-output` tag.)_
- **Respect the repo's PR template.** The guide complements it - keep every required
  `## Section` (Vanta's `pr-template-guard` hook blocks a PR that drops one); just make each
  one tight. Don't delete sections to "simplify."
- **When you cut a code comment that carried real change-context**, fold that context into
  the PR description (or flag it as a candidate inline review comment) rather than losing it.

## Output

1. Show the **rewritten description** in full (all template sections preserved), and a short
   **comment-cleanup list**: each comment you'd remove/simplify as `file:line` → why, with
   the proposed replacement (or "remove").
2. Briefly note what you cut and why, so the user can sanity-check the altitude - but don't
   over-explain; the rewrite should mostly speak for itself.
3. **Wait for approval.** These are outward-facing edits.
4. On OK:
   - Description: `gh pr edit <n> --body "<new body>"` (write the body to a temp file and
     use `--body-file` if it's long or has tricky quoting).
   - Comments: apply the edits to the source files. If the user only wants the description,
     skip this.
   - If there was no PR, just hand over the drafted description - nothing to apply yet.

Never promote a draft PR to ready, never merge, and don't push commits the user didn't ask
for - confirm before any commit that edits code comments.
