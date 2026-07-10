# Verification Evidence

Use this as an internal checklist, not a required PR layout. Preserve the repository's PR template when one exists.

## Required Evidence

- What changed and what risk it carries.
- Verification commands or actions run, with results.
- E2E, browser, or manual evidence when relevant.
- Independent grading or review summary.
- Issues fixed from grading.
- Known gaps or residual risk.

## PR Description

Include only evidence a reviewer cannot infer from CI, such as e2e, browser, manual, or a
reproducible failure-path check. Omit routine unit tests, typecheck, lint, CI status, and the
independent grading notes below.

## Optional Compact Format

Use a table when the evidence is short enough to stay readable:

| Area | Command or action | Result | Evidence |
|---|---|---|---|
| Static checks |  |  |  |
| Tests |  |  |  |
| Build or typecheck |  |  |  |
| E2E, browser, or manual verification |  |  |  |

For longer evidence, use bullets or short paragraphs instead of forcing a table.

## Grading Notes

- Independent reviewer or agent:
- Scope reviewed:
- Findings fixed:
- Findings accepted or deferred:
