# Claude Code hooks vs Cursor hooks

Claude Code uses `.claude/settings.json` with hook types such as `PostToolUse`, `SessionStart`, and matchers (for example `Skill`).

Cursor uses `.cursor/hooks.json` with keys such as `sessionStart`, `stop`, `postToolUse`, `afterShellExecution`, and `subagentStart`.

There is no automatic importer between the two. If you want the same behavior in both products:

1. Keep the shared logic in a small shell script under `.claude/hooks/` or `.cursor/hooks/`.
2. Register that script separately in each product’s hook JSON.
3. Re-test timeouts: Cursor and Claude use different default timeouts and stdin conventions.

Skill sync (`cc-sync-to-cursor-workspace.sh`) does not modify hooks or `permissions.allow` in Claude settings.
