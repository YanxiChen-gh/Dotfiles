# User-Level Claude Code Instructions

## Dotfiles Repo

My Dotfiles repo lives at https://github.com/YanxiChen-gh/Dotfiles. When I mention "my Dotfiles" or "the Dotfiles repo", that's the link.

## Code & PR Authoring

When writing TypeScript code, comments, or PR descriptions on behalf of the user, follow the guide at `~/dotfiles/claude/pr-authoring.md` (worked examples in `pr-examples.md`). The throughline is to optimize for the reader's time and let effort scale with risk. Code avoids `any`/`as`/`!` (except `as const`) and validates untyped boundaries with Zod. Comments and tests get the same bar as code, not nice-to-haves: self-documenting code over filler comments, and no tests written just for coverage. PR descriptions stay high-level (before → problem → after, no diff narration) and scale to the change, so a simple one is often a single line. And all prose should sound like a person wrote it, not an AI.

**Comment self-check before handoff (current models over-comment by default).** Don't just cite the guide — *act on it* before you consider code done. Re-read every comment and test you added and delete any that: narrate the change ("we used to…", "now does X", "Phase 0"), restate what the code already says, are obvious from the symbol name, or only re-verify a library/type/static mapping. Keep only the non-obvious *why* (gotcha, workaround, external constraint). Default to removing; a comment has to earn its place. This check is calibrated to today's verbose models — when the model stops over-commenting, this paragraph is dead weight and should be cut (see the agent-maturity `verbose-output` tag / model-upgrade re-read).

## Verification & PR Handoff

Treat verification as part of the deliverable, not a step after it. Before opening a PR (`gh pr create`):

- **Exercise the running change end-to-end** — drive the actual user-facing path (browser/API/CLI as fits), not just unit tests, and record what you ran and what you saw as a short verification/evidence section in the PR body (`~/dotfiles/shared-skills/full-verification-workflow` + its `evidence-template.md`). A docs-only change just says "docs only, no runtime".
- **Get an independent review before I see it.** Dispatch a clean-context review subagent over the diff + evidence — it didn't write the code, so it catches what you rationalized, and it vets the evidence itself ("did the e2e actually run, or is this a hollow claim?"), re-running a cheap check when the evidence looks thin. Fold its verdict + findings-fixed into the body as a grading section. Grading your own work doesn't count.
- **Minimal by default — comments, tests, and descriptions.** The standing bar (`pr-authoring.md`): add a comment, a test, or a description line only when it earns its place — a non-obvious *why*, real coverage of business logic, motivation the diff can't show. Default is to leave it out. The reviewer checks this explicitly and flags anything present for its own sake.

The `verify-gate` hook enforces this at `gh pr create` (it blocks a PR body with no verification + grading section). It's a backstop, not the mechanism — do the above and it never fires. Escape hatch: `export VERIFY_GATE=off`.

## PR Review Tone

When leaving PR comments, reviews, or code feedback on behalf of the user, follow the tone guide at `~/dotfiles/claude/review-tone.md`. This applies to direct reviews, Paperclip agent reviews, and any automated review workflows.

## Paperclip AI

When the user mentions Paperclip, agents, the CEO, or wants to manage work across repos — load the board persona file first: `load ~/.claude/paperclip.md persona`. This bootstraps the company if needed and gives you the full API reference and agent roster.

## Git Worktrees

After creating a git worktree (any repo), provision it with `~/dotfiles/scripts/provision-worktree.sh <worktree-path>`. It hardlink-seeds `node_modules` from the main checkout (instant, ~0 extra disk) and copies git-ignored local config (`.claude/settings.local.json`, `.dd-agent.env`, `.env*`). It's idempotent and a no-op for anything absent. Don't run `yarn install` / `turbo generate-types` in the worktree unless you'll actually build there — reading and searching need neither.

In Zed remote sessions, worktree *creation* is Zed's job: only worktrees the Zed client creates appear in the sidebar's "Open Worktrees" list (it tracks its own open workspaces, not `git worktree list`). Agent-created worktrees won't show there, but they DO appear in the `git: worktree` picker (`cmd-shift-P`), which lists every `git worktree list` entry — so creating one with `git worktree add` is fine; the user opens it from that picker. There is no ACP path for an external agent to register a worktree into the sidebar.

## MCP Server Preferences

- **Glean MCP**: Use `glean_default` (search, chat, read_document) for all company/internal documentation lookups — Guru cards, Google Docs, Confluence, Slack threads, internal wikis, etc. Glean indexes all internal knowledge sources and respects permissions.
- **Google Drive MCP**: Do NOT use the `google-drive-mcp` tools. Use Glean instead for reading Google Docs and other company documents.
- **Datadog MCP**: Always available for logs, monitors, dashboards, and incident investigation.
- **MongoDB MCP**: If not connected, suggest running `/connect-mongo` to set up the connection. Reference the Guru card for troubleshooting: https://app.getguru.com/card/T6jjXGKc/Connect-to-MongoDB-using-MongoDB-Compass

@RTK.md
