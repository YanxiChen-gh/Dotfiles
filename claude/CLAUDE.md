# User-Level Claude Code Instructions

## Code & PR Authoring

When writing TypeScript code, comments, or PR descriptions on behalf of the user, follow the guide at `~/dotfiles/claude/pr-authoring.md` (worked examples in `pr-examples.md`). The throughline is to optimize for the reader's time and let effort scale with risk. Code avoids `any`/`as`/`!` (except `as const`) and validates untyped boundaries with Zod. Comments and tests get the same bar as code, not nice-to-haves: self-documenting code over filler comments, and no tests written just for coverage. PR descriptions stay high-level (before → problem → after, no diff narration) and scale to the change, so a simple one is often a single line. And all prose should sound like a person wrote it, not an AI.

## Verifying Red Panda / web-app changes

When I make Red Panda or web-app changes — `apps/web-client`, `packages/client-redpanda`, `apps/web`, `packages/web-ai` — that I'll want to verify visually, stand up the local dev server and exercise the change yourself before handing back to me. Run end-to-end tests against the running app as far as you can, driving it through the exposed (Tailscale MagicDNS) URL, and only hand off once you've confirmed the change actually works. Then expose it for my own browser testing, using whichever access method works in the current CDE — the `vanta-dev-server` skill documents the `--tailscale` path and the Ona native port-forward fallback. Give me the browser URL.

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
