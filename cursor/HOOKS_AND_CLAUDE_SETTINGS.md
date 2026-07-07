# Claude Code hooks vs Cursor hooks

Claude Code uses `.claude/settings.json` with hook types such as `PostToolUse`, `SessionStart`, and matchers (for example `Skill`).

Cursor uses `.cursor/hooks.json` with keys such as `sessionStart`, `stop`, `postToolUse`, `afterShellExecution`, and `subagentStart`.

There is no automatic importer between the two. If you want the same behavior in both products:

1. Keep the shared logic in a small shell script under `.claude/hooks/` or `.cursor/hooks/`.
2. Register that script separately in each product’s hook JSON.
3. Re-test timeouts: Cursor and Claude use different default timeouts and stdin conventions.

Skill sync (`sync-claude-skills-to-repo.sh`) does not modify hooks or `permissions.allow` in Claude settings.

### RTK (shared shell hook)

RTK compresses Bash/Shell tool output before it reaches the model. Enabled for **Claude Code**, **OpenAI Codex (GPT)**, and **Cursor**:

- **Cursor** - versioned in [`hooks.json`](hooks.json) (`preToolUse` → `rtk hook cursor`)
- **Claude Code** - patched into `~/.claude/settings.json` (`rtk init -g --hook-only --auto-patch`)
- **Codex** - `~/.codex/AGENTS.md` + `RTK.md` symlinks (instruction-based; prefix commands with `rtk`)

Re-run `install.sh` or `rtk init --show` after changing agents.
