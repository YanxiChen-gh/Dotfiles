# Verification & PR Handoff

Verification is part of the deliverable. Before opening a PR (`gh pr create`), run the workflow in `~/dotfiles/shared-skills/full-verification-workflow` (+ `evidence-template.md`) and put the results in the PR body. Two things that are easy to skip but matter:

- **Exercise the running change end-to-end** (the actual browser/API/CLI path, not just unit tests) and record what you ran - a docs-only change just says "docs only, no runtime".
- **Independent review before handoff** - a clean-context reviewer over the diff + evidence: it catches what you rationalized and vets whether the e2e actually ran. Fold its verdict + fixes into a grading section; grading your own work doesn't count. It also enforces the `pr-authoring.md` minimal bar (a comment/test/description line only if it earns its place).

The PR body must carry that verification + grading section. In Claude Code a `verify-gate` hook blocks `gh pr create` when it's missing (escape hatch `export VERIFY_GATE=off`); other agents have no such hook, so this is on you to include by habit.

For Red Panda / web-app changes (`apps/web-client`, `packages/client-redpanda`, `apps/web`, `packages/web-ai`): stand up the local dev server, exercise the change end-to-end yourself, and hand off only once it actually works. Then expose it for browser testing (see the local-dev-environment rule for port forwarding) and share the URL.
