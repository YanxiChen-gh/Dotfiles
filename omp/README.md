# omp (oh-my-pi) harness - experimental

A parallel harness that runs the same model and the same gates as the opencode
setup, on [oh-my-pi](https://github.com/can1357/oh-my-pi) instead of opencode. It
exists to answer two questions: what does the config look like, and how much of
`dotfiles-harness.js` survives once the harness gives you first-party batteries.

Everything is gated behind `OMP_EXPERIMENT=1` and lives in omp's own `~/.omp`
config dir, so it never runs during a normal install and never touches the live
opencode setup.

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
| Herdr workflow launch (`prefix+a`) | `new-agent-tab.sh` switches on `OMP_EXPERIMENT` |
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

## Documented gaps to verify in a real run

These are places omp's public docs did not fully pin down. The code makes a
best-effort choice and comments it; confirm on your machine before trusting it
beyond the trial.

1. **Root vs subagent discriminator.** omp exposes no guaranteed flag. The Slack
   "finished" notice keys off `session_stop`, which is documented to fire for root
   sessions only. Verify subagents do not page you.
2. **`tool_result` patch shape.** The comment self-check appends its reminder to
   the tool result's content array; confirm the reminder actually reaches the model.
3. **Global `APPEND_SYSTEM.md`.** The rules are linked to `~/.omp/agent/APPEND_SYSTEM.md`;
   confirm omp reads a global one (it definitely reads project `.omp/APPEND_SYSTEM.md`).
4. **Herdr min version.** `herdr integration install omp` needs contract v3; run
   `herdr integration status` to confirm `omp: current (v3)`.

Canary takeover is intentionally not ported - it is coupled to the checkpoint flow
and maturity-data sync. Add it once the trial proves the rest is worth keeping.

## Try it in your real environment

```sh
# 1. Install + link (on your Mac/Ona, where Herdr lives)
export OMP_EXPERIMENT=1
./install.sh                      # runs install_omp + setup_omp_config + install_herdr_omp_integration

# 2. Start omp. OPENAI_API_KEY is discovered automatically when available.
omp                               # otherwise complete native onboarding
herdr integration status          # should show omp: current (v3)

# 3. Run it in a Herdr pane and confirm it shows as an `omp` agent, not a plain shell
omp
```

With `OMP_EXPERIMENT=1` exported in the environment Herdr's server sees (e.g. your
shell profile), the whole workflow follows: `prefix+a` / `prefix+shift+a` launch omp
instead of opencode, and the `--select` picker offers omp. Flag off, everything
reverts to opencode. Override per launch with `HERDR_AGENT_CMD=omp` (or `opencode`).

When seeding an initial prompt via `prefix+a --select`, the launcher passes omp a
mode-600 temporary `@file` argument. omp consumes it after first-run setup, so the
workflow does not depend on a guessed ready string or delay.
The popup uses Enter for a newline, Ctrl+Enter to submit, and Esc to skip.

opencode stays installed and coexists (omp uses its own `~/.omp` dir). Disable the
experiment by unsetting `OMP_EXPERIMENT` and re-running `install.sh`; the opencode
setup is untouched throughout.
