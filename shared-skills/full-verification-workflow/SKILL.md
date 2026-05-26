---
name: full-verification-workflow
description: Run a high-assurance implementation workflow with maximal verification, independent grading, iterative fixes, and draft PR handoff with human-readable evidence.
disable-model-invocation: true
---

# Full Verification Workflow

Use this skill only when the user explicitly invokes `full-verification-workflow`. Once invoked, follow the workflow below, including the independent grading pass.

## Principles

- Treat verification as part of the deliverable.
- Choose the strongest practical verification for the change: unit, integration, typecheck, lint, build, browser/manual, or e2e when risk justifies it.
- Produce evidence that a human reviewer can check and another agent can continue from.
- Use an independent grader/reviewer pass after implementation, then iterate on actionable feedback.
- Finish with draft PRs only, and include verification evidence in each PR body.

## Workflow

1. **Scope and plan**: Clarify success criteria, risk, affected systems, and the verification bar before implementation.
2. **Implement incrementally**: Keep changes reviewable and preserve unrelated user work.
3. **Verify maximally**: Run the most relevant checks for the change. Prefer repo-native commands and include e2e or browser verification when the user-facing workflow or risk warrants it.
4. **Record evidence**: Capture command names, exit codes, important output, screenshots or links when relevant, and any verification gaps.
5. **Grade independently**: Ask a separate agent, reviewer, or equivalent independent pass to review the diff and evidence for correctness, coverage, maintainability, and reviewer-checkability.
6. **Iterate**: Fix actionable grader feedback, rerun affected verification, and repeat grading when the changes are material.
7. **Open draft PRs**: Push reviewable branch(es), create draft PRs, and include the evidence summary plus known residual risks.

## Evidence Format

Use `evidence-template.md` as the required evidence checklist for PR descriptions, handoff notes, and grader prompts. Adapt the presentation to the repository's existing PR template.
