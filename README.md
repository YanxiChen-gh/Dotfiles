# Dotfiles

Personal shell, Cursor, and Claude Code configuration.

## Install layout

`install.sh` is a thin dispatcher: it resolves its own directory, sources every function module under `install.d/*.sh`, then runs the orchestration sequence at the bottom. Each module holds the setup functions for one concern (`10-helpers`, `20-mcp`, `30-system`, `40-cursor`, `50-claude`, `60-codex`, `70-rtk`, `80-tools`, `90-work`); definition order among modules doesn't matter since everything is sourced before the orchestration calls run. `verify-dotfiles.sh` `sh -n`s and shellchecks every module.

## Default shell on Ona

In Vanta's Ona remote dev env (detected via `IS_ON_ONA`), interactive shells default to zsh. `install.sh` adds a runtime-gated guard to `~/.bashrc` that hands interactive bash sessions over to zsh, and best-effort `chsh`'s the login shell when run inside Ona. The guard is a no-op on a personal machine (where `IS_ON_ONA` is unset) — `chsh` alone isn't enough because Ona SSHs in via `exec -l $SHELL -i` with `$SHELL=/bin/bash` and a container's `/etc/passwd` can reset on rebuild.

## Claude Code → Cursor workspace skill sync

`sync-claude-skills-to-repo.sh` copies skills from a repository’s `.claude/skills` and `.claude/plugins/*/skills` into that repo’s `.cursor/skills/_cc_sync/`, rewriting Claude `@file` include lines into explicit “read these paths” instructions for Cursor.

This is **not** `sync-cursor-app-to-dotfiles.sh`, which exports your local Cursor app settings **into** this Dotfiles repo.

### Usage

```sh
# Script resolves its own directory when run via PATH (command -v); README in _cc_sync embeds that path.
sync-claude-skills-to-repo.sh /path/to/work/repo

# Preview
sync-claude-skills-to-repo.sh --dry-run /path/to/obsidian

# Also copy plugin agents to `.cursor/commands/`
sync-claude-skills-to-repo.sh --agents /path/to/obsidian

# Optional JSON at repo root or --config FILE: { "ignore_targets": ["skills-noisy-thing"] }
```

After pulling changes under `.claude/` in a work repo, re-run the script so Cursor sees updated skills.

### Hooks and settings

Claude Code hooks (`PostToolUse`, etc.) and Cursor hooks (`postToolUse`, etc.) are different systems. See [cursor/HOOKS_AND_CLAUDE_SETTINGS.md](cursor/HOOKS_AND_CLAUDE_SETTINGS.md).

### RTK (token-optimized shell output)

[RTK](https://github.com/rtk-ai/rtk) rewrites agent shell commands (`git status`, `cargo test`, `rg`, etc.) to compact output — typically 60–90% fewer tokens on dev workflows. `install.sh` installs the binary and enables it for all three agents:

- **Claude Code** — `PreToolUse` hook in `~/.claude/settings.json` (automatic bash rewrite)
- **OpenAI Codex (GPT)** — [`codex/AGENTS.md`](codex/AGENTS.md) + [`codex/RTK.md`](codex/RTK.md) symlinked to `~/.codex/AGENTS.md` and `RTK.md`
- **Cursor** — `preToolUse` hook in [`cursor/hooks.json`](cursor/hooks.json) (symlinked to `~/.cursor/hooks.json`)

Check savings anytime: `rtk gain`. Telemetry is disabled by default (`RTK_TELEMETRY_DISABLED=1` during install).

**Headroom** ([headroom-ai](https://github.com/chopratejas/headroom)) is not installed by default: it already bundles RTK for shell output, and its Cursor integration routes all model traffic through a local proxy (override API base URL). That conflicts with Cursor’s hosted billing and cloud agents. Install manually if you want MCP/proxy-level compression: `uv tool install 'headroom-ai[proxy,mcp]'`.

### Shared agent rules (single source)

Rules that more than one tool shares live once under `agent-rules/`: a tool-agnostic body (`<name>.md`) plus per-tool settings in `rules.json`. `agent-rules/build.py` compiles them into each tool's native format — today the Cursor `.mdc` files in **both** `cursor/rules/` (personal) and `cursor/rules-work/` (work), per each rule's `scope`. Edit the source and re-run `python3 agent-rules/build.py`; never hand-edit a generated `.mdc`. `verify-dotfiles.sh` runs `build.py --check` and fails on drift, so the copies can't diverge. Adding a tool is a new emitter in `build.py`; adding a rule is a new source file plus a `rules.json` entry.

### Shared global skills (Claude + Cursor)

Skills under `shared-skills/` are symlinked to **both** `~/.claude/skills` and `~/.cursor/skills-cursor` when `WORK_MACHINE=1`, so one copy works in both tools. Cursor-only meta-skills stay under `cursor/skills/`.

### Work monorepo clone

Point the script at your local checkout (no repo changes required there): `sync-claude-skills-to-repo.sh ~/path/to/obsidian`. Generated files under that clone’s `.cursor/skills/_cc_sync/` are local-only unless you choose to commit them later as a team decision.

## Verifying changes

From the repo root:

```sh
./scripts/verify-dotfiles.sh
```

This runs:

1. **`sh -n`** on `install.sh`, `install.d/*.sh`, `sync-claude-skills-to-repo.sh`, `sync-cursor-app-to-dotfiles.sh`, `shell/work.sh`, and the verify script itself.
2. **`python3 -m py_compile`** on [`scripts/sync_cursor_mcp_from_claude.py`](scripts/sync_cursor_mcp_from_claude.py) when present (syntax check).
3. **`shellcheck -S error`** on those shell files when `shellcheck` is installed (warnings are ignored so existing style nits do not fail the run).
4. **Integration:** copies [`test-fixtures/minimal-claude-workspace/`](test-fixtures/minimal-claude-workspace/) to a temp directory, runs `sync-claude-skills-to-repo.sh` on it, and checks that `SKILL.md` was rewritten (`## Required context` and the former `@` path). **Requires `python3`** for that transform.
5. **E2E:** [`tests/e2e/run.sh`](tests/e2e/run.sh) (MCP Claude → Cursor sync script; isolated temp dirs, does not touch your real `~/.cursor`). **Requires `python3`.**

Fast check without integration or e2e:

```sh
./scripts/verify-dotfiles.sh --quick
```

Use this before pushing or when editing shell scripts. Full `install.sh` with a throwaway `HOME` is still useful for release-style validation but is slow and can touch MCP/network; the verify script is the default loop.

### CI

[GitHub Actions](.github/workflows/ci.yml) runs `./scripts/verify-dotfiles.sh` on every push and pull request to `main` / `master`. See [CONTRIBUTING.md](CONTRIBUTING.md) for expectations on changes to this repo.
