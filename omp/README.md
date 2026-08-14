# omp (oh-my-pi) harness

A parallel harness that runs the same model and the same gates as the opencode
setup, on [oh-my-pi](https://github.com/can1357/oh-my-pi) instead of opencode. It
exists to answer two questions: what does the config look like, and how much of
`dotfiles-harness.js` survives once the harness gives you first-party batteries.

omp is enabled by default and lives in its own `~/.omp` config directory, so it
coexists with OpenCode. Set `OMP_EXPERIMENT=0` to skip omp setup and make the
Herdr workflow default to OpenCode.

## How much shrinks

| | opencode | omp |
| --- | ---: | ---: |
| Harness plugin/extension | 1,813 | 287 |
| Model + agent config | 37 | 0 |
| Auto-mode wrapper | 70 | 0 |
| Install module | 126 | 181 |
| **Total** | **2,046** | **468** |

The plugin drops ~85%. The reason is not cleverness - it is that omp provides
first-party what opencode made us rebuild:

| Capability | opencode had to build it | omp |
| --- | --- | --- |
| Herdr title/subagent/state sync | ~500 lines of `report-metadata` plumbing | native lifecycle + Agent Hub; small workspace-title bridge kept |
| Root vs subagent lineage | hydrate + walk `parentID` | tracked natively (see gaps) |
| Event ordering / dedupe queues | ~120 lines | typed, ordered lifecycle events |
| Same-session checkpoint/compaction | ~400 lines | native auto-compaction |
| Auto mode | wrapper script | native `yolo` default |
| Scope / verify / PR / comment gates | kept | **kept, ported verbatim** |
| Slack attention | kept | kept, slimmer |
| Canary takeover | ~300 lines | deferred (see below) |

The gates are the point, and they port almost unchanged: `dotfiles-harness.ts`
shells out to the exact same `agent-maturity` and `claude/hooks` scripts, with the
same JSON-stdin / exit-code-2 contract. What disappeared was the scaffolding
around them.

## Layout

- `agent/extensions/dotfiles-harness.ts` - the ported gates, Herdr title bridge, and Slack notifier.
- `install.d/66-omp.sh` links these into `~/.omp/agent/`, runs the Herdr
  integration, registers RTK (best-effort), and syncs the Glean MCP overlay.
  With `OPENAI_API_KEY`, setup selects `openai/gpt-5.6-sol` without overriding
  its model-default reasoning level. Otherwise omp's native onboarding owns setup.

## Parity with the opencode setup

Every piece of the opencode integration, mapped to its omp equivalent:

| opencode | omp |
| --- | --- |
| Model + agents | `openai/gpt-5.6-sol` via `OPENAI_API_KEY`; native onboarding when absent |
| Auto mode (`--auto` wrapper) | Native `yolo` default |
| Scope / verify / PR / comment gates | ported in `dotfiles-harness.ts` (same scripts) |
| Slack attention notifications | ported in `dotfiles-harness.ts` |
| Herdr session/subagent/state sync | native `herdr integration install omp`; workspace title mirrored by the harness |
| Same-session checkpoint/compaction | native auto-compaction |
| Global rules (`AGENTS.md`) | `APPEND_SYSTEM.md` (linked) |
| Skills: `~/.claude/skills` + `~/.agents/skills` (shared, advisor, agent-maturity) | **native** - omp's Claude + Agents providers read the same dirs |
| Glean MCP overlay (`sync_opencode_mcp_from_claude.py`) | `sync_omp_mcp_from_claude.py` -> `~/.omp/agent/mcp.json` |
| RTK token-optimized shell output | `rtk init --agent omp` (best-effort; may be unsupported) |
| Herdr workflow launch (`prefix+a`) | omp by default; `OMP_EXPERIMENT=0` selects OpenCode |
| `opencode-claude-auth` (Anthropic SSO) | Native setup and `/login` |
| Canary takeover | deferred (checkpoint/maturity-coupled) |
| `vanta-doc-discovery` work Glean adapter | not ported - verify the Claude skill works over MCP first |
| `tui.jsonc` | not ported (cosmetic TUI prefs) |

The skills row is the important one: omp discovers `~/.claude/skills` and
`~/.agents/skills` natively, so the shared, advisor, agent-maturity, and Claude
Code skills you already symlink there show up in omp with zero extra config.
The native Agent Hub owns subagent detail. Herdr remains the cross-workspace
lifecycle view and does not duplicate omp's task list.

Lavish review is allowed only in a human-interactive omp TUI. Run its safe poll
as one managed async Bash job per feedback round; omp delivers completion back
to the session, so no periodic polling or detached shell process is needed.

## Operational notes

The trial exercised standard OpenAI requests, gate loading, managed Lavish jobs,
Herdr title sync, multiline prompts, and Agent Hub behavior. Keep these lifecycle
details in mind when troubleshooting:

1. Slack completion uses omp's root-only `session_stop`; task agents do not emit it.
2. Global rules are linked at `~/.omp/agent/APPEND_SYSTEM.md`.
3. Run `herdr integration status` after Herdr upgrades and confirm `omp: current`.

Canary takeover is intentionally not ported - it is coupled to the checkpoint flow
and maturity-data sync. Add it once the trial proves the rest is worth keeping.

## Try it in your real environment

```sh
# 1. Install + link (on your Mac/Ona, where Herdr lives)
./install.sh                      # runs install_omp + setup_omp_config + install_herdr_omp_integration

# 2. Start omp. OPENAI_API_KEY is discovered automatically when available.
omp                               # otherwise complete native onboarding
herdr integration status          # should show omp: current (v3)

# 3. Run it in a Herdr pane and confirm it shows as an `omp` agent, not a plain shell
omp
```

The whole workflow follows the default: `prefix+a` / `prefix+shift+a` launch omp,
and the `--select` picker offers omp. If omp is unavailable, the launcher falls
back to OpenCode. Set `HERDR_AGENT_CMD=opencode` (or `omp`) in the environment
before starting Herdr to override its server-wide default.

When seeding an initial prompt via `prefix+a --select`, the launcher passes omp a
mode-600 temporary `@file` argument. omp consumes it after first-run setup, so the
workflow does not depend on a guessed ready string or delay.
The popup uses Enter for a newline, Ctrl+S to submit, and Esc to skip.
Encoded Ctrl+Enter remains supported when the host terminal preserves it.

OpenCode stays installed and coexists with omp. To make it the default again,
persist the opt-out in the environment Herdr's server inherits, rerun setup, and
restart an already-running server from outside its attached client:

```sh
export OMP_EXPERIMENT=0
./install.sh
herdr server stop
herdr
```

This skips omp integration work and makes `prefix+a` launch OpenCode. It does not
need to uninstall the existing omp binary. Run the stop/start sequence from a
shell outside the attached Herdr client. Remove the override or set it to `1`
and restart the server to return to omp.
