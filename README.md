# Dotfiles

Personal shell, Cursor, and Claude Code configuration.

## Claude Code → Cursor workspace skill sync

`cc-sync-to-cursor-workspace.sh` copies skills from a repository’s `.claude/skills` and `.claude/plugins/*/skills` into that repo’s `.cursor/skills/_cc_sync/`, rewriting Claude `@file` include lines into explicit “read these paths” instructions for Cursor.

This is **not** `cursor-sync.sh`, which exports your local Cursor app settings **into** this Dotfiles repo.

### Usage

```sh
# Script resolves its own directory when run via PATH (command -v); README in _cc_sync embeds that path.
cc-sync-to-cursor-workspace.sh /path/to/work/repo

# Preview
cc-sync-to-cursor-workspace.sh --dry-run /path/to/obsidian

# Also copy plugin agents to .cursor/commands/
cc-sync-to-cursor-workspace.sh --agents /path/to/obsidian

# Optional JSON at repo root or --config FILE: { "ignore_targets": ["skills-noisy-thing"] }
```

After pulling changes under `.claude/` in a work repo, re-run the script so Cursor sees updated skills.

### Hooks and settings

Claude Code hooks (`PostToolUse`, etc.) and Cursor hooks (`postToolUse`, etc.) are different systems. See [cursor/HOOKS_AND_CLAUDE_SETTINGS.md](cursor/HOOKS_AND_CLAUDE_SETTINGS.md).

### Shared global skills (Claude + Cursor)

Skills under `shared-skills/` are symlinked to **both** `~/.claude/skills` and `~/.cursor/skills-cursor` when `WORK_MACHINE=1`, so one copy works in both tools. Cursor-only meta-skills stay under `cursor/skills/`.

### Work monorepo clone

Point the script at your local checkout (no repo changes required there): `cc-sync-to-cursor-workspace.sh ~/path/to/obsidian`. Generated files under that clone’s `.cursor/skills/_cc_sync/` are local-only unless you choose to commit them later as a team decision.

## Verifying changes

From the repo root:

```sh
./scripts/verify-dotfiles.sh
```

This runs:

1. **`sh -n`** on `install.sh`, `cc-sync-to-cursor-workspace.sh`, `cursor-sync.sh`, `shell/work.sh`, and the verify script itself.
2. **`shellcheck -S error`** on those files when `shellcheck` is installed (warnings are ignored so existing style nits do not fail the run).
3. **Integration:** copies [`test-fixtures/minimal-claude-workspace/`](test-fixtures/minimal-claude-workspace/) to a temp directory, runs `cc-sync-to-cursor-workspace.sh` on it, and checks that `SKILL.md` was rewritten (`## Required context` and the former `@` path). **Requires `python3`** for that transform.

Fast check without integration:

```sh
./scripts/verify-dotfiles.sh --quick
```

Use this before pushing or when editing shell scripts. Full `install.sh` with a throwaway `HOME` is still useful for release-style validation but is slow and can touch MCP/network; the verify script is the default loop.
