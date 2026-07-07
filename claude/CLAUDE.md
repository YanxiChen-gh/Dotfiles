# User-Level Claude Code Instructions

## Dotfiles Repo

My Dotfiles repo lives at https://github.com/YanxiChen-gh/Dotfiles. When I mention "my Dotfiles" or "the Dotfiles repo", that's the link.

## Writing Style

Never use the em dash ("—"). Use a plain hyphen ("-") instead. This applies to everything you write on my behalf: chat responses, code, code comments, commit messages, PR descriptions, and docs.

## Engineering Principles

- Weigh technical decisions on quality, simplicity, robustness, scalability, and long-term maintainability, not on how much effort they take to build. Development cost is a minor factor.
- Fix bugs reproduction-first: before changing anything, reproduce the bug end-to-end, as close to how an end user hits it as possible. That confirms you have found the real cause so the fix actually solves it.
- When testing a product end-to-end, be picky about the UI and obsessed with pixel perfection. If something looks off, even when it is unrelated to your current change, get it fixed along the way.
- Hold the same bar for engineering excellence: lint errors, test failures, and flaky tests. If you see one, fix it even when your current work did not cause it. In my personal repos (for example Dotfiles) you can push the fix straight to main once verified; this does not override project rules that require pull requests (for example the Vanta monorepo: draft PRs only, never merge your own).

## Code & PR Authoring

When writing TypeScript code, comments, or PR descriptions on my behalf, follow `~/dotfiles/claude/pr-authoring.md` (worked examples in `pr-examples.md`). Throughline: optimize for the reader's time, let effort scale with risk.

**Comment self-check before handoff** — current models over-comment, so act on the guide's comment bar, don't just cite it: after writing, re-read every comment and test you added and delete any that narrate the change, restate the code, are obvious from the name, or only re-verify a type/mapping; keep only the non-obvious *why*. (A `comment-self-check.sh` PostToolUse hook also nudges this; retire this note when models stop over-commenting — the agent-maturity `verbose-output` tag.)

## Commits & Generated Files

- Never add yourself (the AI agent) as a commit co-author. Do not append `Co-Authored-By:` trailers naming Claude, Codex, Cursor, or any agent, and do not add agent attribution to commit messages or PR descriptions unless I explicitly ask.
- Never hand-edit `CHANGELOG.md` files or any file marked as auto-generated (generated-header banners, lockfiles, codegen output, build artifacts). Change the source and regenerate instead.

## Planning Artifacts

For any plan, design doc, or pre-implementation review artifact (plan mode included), default to a **Lavish HTML artifact** I open and annotate in the browser (`npx -y lavish-axi <file>`), not a markdown file — make it rich (sections, diagrams, comparisons, decision inputs), then `npx -y lavish-axi poll` for my feedback and iterate. Fall back to markdown only when Lavish is unavailable or it's a throwaway one-liner.

## Verification & PR Handoff

Verification is part of the deliverable. Before `gh pr create`, run the workflow in `~/dotfiles/shared-skills/full-verification-workflow` (+ `evidence-template.md`) and put the results in the PR body. Two things it's easy to skip but I care about:

- **Exercise the running change end-to-end** (the actual browser/API/CLI path, not just unit tests) and record what you ran — a docs-only change just says "docs only, no runtime".
- **Independent review before I see it** — a clean-context subagent over the diff + evidence: it catches what you rationalized and vets whether the e2e actually ran. Fold its verdict + fixes into a grading section; grading your own work doesn't count. It also enforces the `pr-authoring.md` minimal bar (a comment/test/description line only if it earns its place).

The `verify-gate` hook backstops this at `gh pr create` (blocks a body missing the verification + grading section); do the above and it never fires. Escape hatch: `export VERIFY_GATE=off`.

## Verifying Red Panda / web-app changes

For Red Panda / web-app changes (`apps/web-client`, `packages/client-redpanda`, `apps/web`, `packages/web-ai`) I'll want to see: stand up the local dev server, exercise the change end-to-end yourself, and only hand off once it actually works. Then expose it for my own browser testing (see Exposing Local Dev Servers below; the `vanta-dev-server` skill covers the `--tailscale` path) and give me the URL.

## PR Review Tone

When leaving PR comments, reviews, or code feedback on behalf of the user, follow the tone guide at `~/dotfiles/claude/review-tone.md`. This applies to direct reviews and any automated review workflows.

## Git Worktrees

After creating a git worktree (any repo), provision it with `~/dotfiles/scripts/provision-worktree.sh <path>` — it hardlink-seeds `node_modules` and copies git-ignored local config (`.claude/settings.local.json`, `.dd-agent.env`, `.env*`); idempotent, no-op for anything absent. Don't run `yarn install` / `turbo generate-types` in a worktree unless you'll actually build there.

In Zed remote sessions, agent-created worktrees don't appear in the sidebar's "Open Worktrees" list, but they do show in the `git: worktree` picker (`cmd-shift-P`) — so `git worktree add` is fine; I open it from there.

## Exposing Local Dev Servers (Port Forwarding)

To reach a local server on a remote CDE from my laptop, prefer in order:

1. **`~/dotfiles/scripts/expose-port-tailscale.sh <local-port> [verify-path]`** (preferred) — handles the whole Ona/tailnet chain and verifies through the tailnet path. It encodes two hard-won constraints; don't work around them by hand: serve on **tailnet port 8080 only** (ACLs for `tag:ona-dev` admit only that port — others hang from a laptop while self-tests still pass), and **verify through the tailnet path, not a localhost curl**.
2. **Editor port-forward** — VS Code/Cursor Ports panel (needs my click).
3. **ngrok** — last resort (public URL; tear it down when done).

Don't use a static share/publish/export when you need a *live* server — it drops the interactive connection back to the agent.

## MCP Server Preferences

- **Glean MCP**: Use `glean_default` (search, chat, read_document) for all company/internal documentation lookups — Guru cards, Google Docs, Confluence, Slack threads, internal wikis, etc. Glean indexes all internal knowledge sources and respects permissions.
- **Google Drive MCP**: Do NOT use the `google-drive-mcp` tools. Use Glean instead for reading Google Docs and other company documents.
- **Datadog MCP**: Always available for logs, monitors, dashboards, and incident investigation.
- **MongoDB MCP**: If not connected, suggest running `/connect-mongo` to set up the connection. Reference the Guru card for troubleshooting: https://app.getguru.com/card/T6jjXGKc/Connect-to-MongoDB-using-MongoDB-Compass

@RTK.md
