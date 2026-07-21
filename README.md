# Dotfiles

Personal shell and agent configuration for Claude Code, OpenCode, Codex, and Cursor.

## Install layout

`install.sh` is a thin dispatcher: it resolves its own directory, sources every function module under `install.d/*.sh`, then runs the orchestration sequence at the bottom. Each module holds the setup functions for one concern (`10-helpers`, `20-mcp`, `30-system`, `40-cursor`, `50-claude`, `60-codex`, `65-opencode`, `70-rtk`, `80-tools`, `90-work`); definition order among modules doesn't matter since everything is sourced before the orchestration calls run. `verify-dotfiles.sh` `sh -n`s and shellchecks every module.

## Default shell on Ona

In Vanta's Ona remote dev env (detected via `IS_ON_ONA`), interactive shells default to zsh. `install.sh` adds a runtime-gated guard to `~/.bashrc` that hands interactive bash sessions over to zsh, and best-effort `chsh`'s the login shell when run inside Ona. The guard is a no-op on a personal machine (where `IS_ON_ONA` is unset) - `chsh` alone isn't enough because Ona SSHs in via `exec -l $SHELL -i` with `$SHELL=/bin/bash` and a container's `/etc/passwd` can reset on rebuild.

## Editor (Vim / Neovim)

`.vimrc` at the repo root is symlinked to `~/.vimrc` by `create_symlinks` (vim-plug installs any missing plugins on startup). Neovim reads `~/.config/nvim/init.vim` rather than `~/.vimrc`, so `setup_nvim_config` links `nvim/init.vim` (which sources `~/.vimrc`) and `nvim/lsp.lua` there. Neovim uses its native LSP client with project-local TypeScript 7 `tsgo` when available and Mason's `typescript-language-server` with a pinned TypeScript 6 language-service fallback otherwise. Mason also installs and configures Bash and Go language servers; Java and OCaml servers are included when Java 21+ and opam are available.

For TypeScript navigation in Neovim, `gd` prefers the source implementation, `gD` requests the protocol definition, `Ctrl-w ]` opens a definition in a split, `gy` opens the type definition, `gi` opens implementations, `gr` lists references, and `K` shows documentation. Use `Ctrl-o` and `Ctrl-i` to move backward and forward through the jump list. Run `:checkhealth vim.lsp` when a server does not attach.

Run `:Mason` to inspect managed language servers. In that window, `U` updates every installed tool; `:MasonUpdate` refreshes the package registry. Use `:checkhealth mason` for installation problems and `:checkhealth vim.lsp` for server attachment or root-detection problems.

If you already keep a hand-managed `~/.config/nvim/init.vim`, note that `install.sh` replaces it with this symlink (same declarative-clobber behavior as the other dotfile links).

## Terminal colors (iTerm2)

`terminal/gruvbox-dark.itermcolors` is the iTerm2 color preset. iTerm imports presets through its GUI, not a symlink: **Settings → Profiles → Colors → Color Presets → Import…**, pick the file, then select it from the same menu.

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

[RTK](https://github.com/rtk-ai/rtk) rewrites agent shell commands (`git status`, `cargo test`, `rg`, etc.) to compact output - typically 60–90% fewer tokens on dev workflows. `install.sh` installs the binary and enables it for all four agents:

- **Claude Code** - `PreToolUse` hook in `~/.claude/settings.json` (automatic bash rewrite)
- **OpenCode** - `tool.execute.before` plugin in `~/.config/opencode/plugins/rtk.ts`
- **OpenAI Codex (GPT)** - [`codex/AGENTS.md`](codex/AGENTS.md) + [`codex/RTK.md`](codex/RTK.md) symlinked to `~/.codex/AGENTS.md` and `RTK.md`
- **Cursor** - `preToolUse` hook in [`cursor/hooks.json`](cursor/hooks.json) (symlinked to `~/.cursor/hooks.json`)

Check savings anytime: `rtk gain`. Telemetry is disabled by default (`RTK_TELEMETRY_DISABLED=1` during install).

**Headroom** ([headroom-ai](https://github.com/chopratejas/headroom)) is not installed by default: it already bundles RTK for shell output, and its Cursor integration routes all model traffic through a local proxy (override API base URL). That conflicts with Cursor’s hosted billing and cloud agents. Install manually if you want MCP/proxy-level compression: `uv tool install 'headroom-ai[proxy,mcp]'`.

### Shared agent rules (single source)

Rules that more than one tool shares live once under `agent-rules/`: a tool-agnostic body (`<name>.md`) plus per-tool settings in `rules.json`. Each rule's canonical `scope` is `personal`, `work`, or `both` (the default). `agent-rules/build.py` compiles scoped aggregates for Claude, Codex, and OpenCode plus Cursor `.mdc` files under `cursor/rules/` and `cursor/rules-work/`. The installer selects work aggregates only when `WORK_MACHINE=1`. Edit the source and re-run `python3 agent-rules/build.py`; never hand-edit generated instructions. `verify-dotfiles.sh` runs `build.py --check` and fails on drift, so the copies can't diverge. Adding a tool is a new emitter in `build.py`; adding a rule is a new source file plus a `rules.json` entry.

### OpenCode

`install.sh` installs OpenCode with the official installer, links [`opencode/opencode.jsonc`](opencode/opencode.jsonc) into `$XDG_CONFIG_HOME/opencode/` (default `~/.config/opencode/`), and preserves the existing GPT-5.6 agent defaults. Existing unmanaged files are moved once to a `.pre-dotfiles` backup rather than deleted. [`opencode-claude-auth`](https://github.com/griffinmartin/opencode-claude-auth) is pinned and loaded as an npm plugin so Anthropic models can reuse Claude Code's SSO credentials without storing them in this repo. It is a community workaround that may be affected by Anthropic's terms or OAuth changes. On macOS it also copies credentials from Keychain into OpenCode's mode-`0600` `auth.json`; Linux already uses Claude Code's credentials file.

OpenCode gets the same generated global rules, auto-discovers skills under `~/.claude/skills` and `~/.agents/skills`, and uses a local plugin adapter for the scope, comment, verification, and PR-authoring gates. On work machines it also links an OpenCode-specific `vanta-doc-discovery` adapter that reads the current Obsidian worktree's repository skill and maps its Claude-specific Glean calls to OpenCode's Glean tools. Herdr installs its official OpenCode plugin for lifecycle state and session restore, and RTK installs its native OpenCode plugin. Claude Code MCP definitions are converted to an untracked, mode-`0600` `$XDG_CONFIG_HOME/opencode/mcp.json` overlay at install time. Servers that require Claude's unsupported dynamic `headersHelper` are reported and skipped rather than silently misconfigured.

After changing OpenCode config or plugins, quit and restart OpenCode. To use Claude SSO, authenticate Claude Code first, then select an Anthropic model in OpenCode.

### Shared global skills (Claude + OpenCode + Cursor + Codex)

Skills under `shared-skills/` are symlinked to `~/.claude/skills`, `~/.cursor/skills-cursor`, and the open Agent Skills path at `~/.agents/skills` when `WORK_MACHINE=1`, so one copy works across tools. Claude Code, Codex, OpenCode, and Cursor discover them natively. Cursor-only meta-skills stay under `cursor/skills/`.

### Google Workspace CLI

On work machines, `install.sh` pins and installs [`gws`](https://github.com/googleworkspace/cli). Run `gws-work-auth` once per fresh machine to authorize Docs, Sheets, Slides, and the Drive operations used for comments, permissions, and file metadata. The helper is idempotent, accepts only a valid `@vanta.com` account, and deliberately uses explicit scopes so `gws` does not add `cloud-platform` access.

The OAuth client is shared configuration, not a per-machine Cloud project. Supply `GOOGLE_WORKSPACE_CLI_CLIENT_ID` and `GOOGLE_WORKSPACE_CLI_CLIENT_SECRET` through work secrets; Dotfiles syncs only those two Google Workspace values from Ona to Cursor Cloud. Alternatively, place the existing desktop client at `~/.config/gws/client_secret.json`. Never commit that file, `credentials.enc`, `.encryption_key`, or an exported refresh token. The helper rejects access-token and external-credentials-file overrides. Cursor's hybrid port forwarding normally handles the random localhost OAuth callback in a remote environment; if it does not, forward the printed port in the Ports panel before opening the URL.

### Agent maturity

The agent-maturity bootstrap installs one model-agnostic engine and private data store. Claude Code uses native lifecycle hooks, Codex uses the same hook scripts through `~/.codex/hooks.json`, and OpenCode uses `dotfiles-harness.js` to adapt its plugin events. All three discover the same skills without copying them. Codex requires a one-time `/hooks` review after installation or whenever the hook definition changes.

### Work monorepo clone

Point the script at your local checkout (no repo changes required there): `sync-claude-skills-to-repo.sh ~/path/to/obsidian`. Generated files under that clone’s `.cursor/skills/_cc_sync/` are local-only unless you choose to commit them later as a team decision.

## Verifying changes

From the repo root:

```sh
./scripts/verify-dotfiles.sh
```

This runs:

1. **`sh -n`** on `install.sh`, `install.d/*.sh`, `sync-claude-skills-to-repo.sh`, `sync-cursor-app-to-dotfiles.sh`, `shell/work.sh`, and the verify script itself.
2. **`node --check`** on OpenCode plugins when Node.js is installed.
3. **`python3 -m py_compile`** on MCP sync scripts and the agent-rules generator.
4. **`shellcheck -S error`** on those shell files when `shellcheck` is installed (warnings are ignored so existing style nits do not fail the run).
5. **Integration:** copies [`test-fixtures/minimal-claude-workspace/`](test-fixtures/minimal-claude-workspace/) to a temp directory, runs `sync-claude-skills-to-repo.sh` on it, and checks that `SKILL.md` was rewritten (`## Required context` and the former `@` path). **Requires `python3`** for that transform.
6. **E2E:** [`tests/e2e/run.sh`](tests/e2e/run.sh) covers MCP sync and isolated OpenCode config/harness linking without touching real user config. **Requires `python3`.**

Fast check without integration or e2e:

```sh
./scripts/verify-dotfiles.sh --quick
```

Use this before pushing or when editing shell scripts. Full `install.sh` with a throwaway `HOME` is still useful for release-style validation but is slow and can touch MCP/network; the verify script is the default loop.

### CI

[GitHub Actions](.github/workflows/ci.yml) runs `./scripts/verify-dotfiles.sh` on every push and pull request to `main` / `master`. See [CONTRIBUTING.md](CONTRIBUTING.md) for expectations on changes to this repo.
