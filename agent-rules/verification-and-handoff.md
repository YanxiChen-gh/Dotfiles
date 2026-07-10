# Verification & PR Handoff

Verification is part of the deliverable. Before opening a PR (`gh pr create`), run the workflow in `~/dotfiles/shared-skills/full-verification-workflow` (+ `evidence-template.md`). Put only the reviewer-useful results in the PR body. Two things that are easy to skip but matter:

- **Exercise the running change end-to-end** (the actual browser/API/CLI path, not just unit tests) and record what you ran - a docs-only change just says "docs only, no runtime".
- **Independent review before handoff** - a clean-context reviewer over the diff + evidence: it catches what you rationalized and vets whether the e2e actually ran. Apply its findings before opening the PR, but keep the verdict and grading notes in the handoff record rather than adding process ceremony to the PR description. Grading your own work doesn't count. It also enforces the `pr-authoring.md` minimal bar (a comment/test/description line only if it earns its place).

The PR body should carry only verification a reviewer cannot infer from CI, such as e2e, browser, manual, or reproducible failure-path evidence. Omit routine unit-test, typecheck, lint, and CI status, and do not add an independent-review or grading section.

<!--claude-only-->
The `verify-gate` hook backstops this at `gh pr create` (blocks a body missing verification evidence); do the above and it never fires. It only fires on work-org repos (default `VantaInc`), so personal repos are never gated. Escape hatch: `export VERIFY_GATE=off`.
<!--/claude-only-->


For Red Panda / web-app changes (`apps/web-client`, `packages/client-redpanda`, `apps/web`, `packages/web-ai`): stand up the local dev server, exercise the change end-to-end yourself, and hand off only once it actually works. Then expose it for browser testing (see the local-dev-environment rule for port forwarding) and share the URL.
