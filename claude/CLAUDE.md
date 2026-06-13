# User-Level Claude Code Instructions

## Code & PR Authoring

When writing TypeScript code, code comments, or PR descriptions on behalf of the user, follow the guide at `~/dotfiles/claude/pr-authoring.md`. In short: optimize for the reader's time and let effort scale with risk. Code avoids `any`/`as`/`!` (model the type instead), validates untyped boundaries with Zod, prefers discriminated results over throwing for control flow, puts auth in the service not the caller, and never swallows errors silently. Comments and tests get the same bar as code (not nice-to-haves): prefer self-documenting code and comment only the non-obvious *why* (a load-bearing comment can be long; delete restating/stale/AI filler), and never test for coverage's sake — no tests of libraries or trivial mappings, and a complex or heavily-mocked test is a red flag to fix via dependency injection. Descriptions are concise and high-level (before → problem → after, no diff narration) and scale to the change — for a simple change the whole Changes section is often one line ("refactor X to Y so that Z") or TIN, spending words only on what the diff can't show. Motivation states the root cause in a line, testing shows only the hard stuff as evidence and skips the obvious, and inapplicable template sections get deleted rather than left empty. All prose should sound like a person wrote it — vary sentence length, plain words over exhaustive jargon, no formula openers or em-dash pileups.

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
