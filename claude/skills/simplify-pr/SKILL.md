---
name: simplify-pr
description: Tighten a PR description and code comments against Yanxi's canonical PR style. Use only when explicitly invoked, such as "/simplify-pr" or "simplify this PR".
disable-model-invocation: true
---

# Simplify PR

Use `~/dotfiles/claude/pr-authoring.md` as the only substantive style standard. If that path does
not resolve, read `../../pr-authoring.md` relative to this skill.

## Resolve the target

1. Use the explicit PR URL or number, if supplied.
2. Otherwise use the current branch's PR: `gh pr view --json number,title,body,url`.
3. If no PR exists, work from the branch diff and return a draft description. Say that nothing
   has been published.

Read the current description, actual diff, and commits. For a PR, use `gh pr diff <n>` and
`gh pr view <n> --json title,body,commits`. For an unpublished branch, inspect its diff and commits
against the repository's base branch.

## Make a surgical proposal

For each proposed edit, record the exact span, the violated guide rule, and the smallest fix.
Leave spans without a concrete violation unchanged, including their placement and formatting.
Focus on the description and comments; flag unit-test violations rather than rewriting tests.
Do not refactor feature code as part of a style cleanup.

Preserve required template sections and necessary reader-facing meaning, such as caller impact,
compatibility, permissions, deployment constraints, and verification evidence. Existing claims are
not automatically protected: judge them against the shared standard before retaining them.
Compare the rewrite with the input and restore necessary meaning that was lost or weakened.
Cut private drafting history rather than relocating it to the description.

## Output and approval

Return the rewritten description and a short edit ledger. Locate comment changes with `file:line`.
Keep the ledger outside the description. If there are no concrete violations, say so and do not
manufacture changes.

Wait for approval before changing an existing PR description or applying proposed source edits.
On approval, use `gh pr edit <n> --body-file <file>` for the description and apply only the approved
source edits. If there is no PR, return the draft without publishing it. Respect narrower requests,
such as description-only cleanup.

Do not promote a draft, merge, or push. Commit only when explicitly requested.
