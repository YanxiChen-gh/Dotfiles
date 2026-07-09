---
name: full-verification-workflow
description: Run a high-assurance implementation workflow with maximal verification, independent grading, iterative fixes, and human-readable handoff evidence.
---

# Full Verification Workflow

Use this skill before opening a PR or when the user explicitly requests a high-assurance verification workflow. Follow the workflow below, including the independent grading pass.

## Principles

- Treat verification as part of the deliverable.
- Choose the strongest practical verification for the change: unit, integration, typecheck, lint, build, browser/manual, or e2e when risk justifies it.
- Produce evidence that a human reviewer can check and another agent can continue from.
- Use an independent grader/reviewer pass after implementation, then iterate on actionable feedback.
- Complete only the handoff actions the user authorized. When opening a PR, create it as a draft and include verification evidence in its body.

## Workflow

1. **Scope and plan**: Clarify success criteria, risk, affected systems, and the verification bar before implementation.
2. **Implement incrementally**: Keep changes reviewable and preserve unrelated user work.
3. **Verify maximally**: Run the most relevant checks for the change. Prefer repo-native commands and include e2e or browser verification when the user-facing workflow or risk warrants it.
4. **Record evidence**: Capture command names, exit codes, important output, screenshots or links when relevant, and any verification gaps.
5. **Grade independently**: Ask a separate agent, reviewer, or equivalent independent pass to review the diff and evidence for correctness, coverage, maintainability, and reviewer-checkability.
6. **Iterate**: Fix actionable grader feedback, rerun affected verification, and repeat grading when the changes are material.
7. **Complete the requested handoff**: Commit, push, or open a PR only when explicitly requested. Create PRs as drafts and include the evidence summary plus known residual risks.

## Evidence Format

Use `evidence-template.md` as the required evidence checklist for PR descriptions, handoff notes, and grader prompts. Adapt the presentation to the repository's existing PR template.
