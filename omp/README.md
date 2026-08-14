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
| Harness plugin/extension | 1,813 | 210 |
| Model + agent config | 37 | 53 |
| Auto-mode wrapper | 70 | 0 |
| Install module | 126 | 87 |
| **Total** | **2,046** | **350** |

The plugin drops ~88%. The reason is not cleverness - it is that omp provides
first-party what opencode made us rebuild:

| Capability | opencode had to build it | omp |
| --- | --- | --- |
| Herdr title/subagent/state sync | ~500 lines of `report-metadata` plumbing | `herdr integration install omp` (native lifecycle + session restore) |
| Root vs subagent lineage | hydrate + walk `parentID` | tracked natively (see gaps) |
| Event ordering / dedupe queues | ~120 lines | typed, ordered lifecycle events |
| Same-session checkpoint/compaction | ~400 lines | native auto-compaction |
| Auto mode | wrapper script | `tools.approvalMode` config |
| Scope / verify / PR / comment gates | kept | **kept, ported verbatim** |
| Slack attention | kept | kept, slimmer |
| Canary takeover | ~300 lines | deferred (see below) |

The gates are the point, and they port almost unchanged: `dotfiles-harness.ts`
shells out to the exact same `agent-maturity` and `claude/hooks` scripts, with the
same JSON-stdin / exit-code-2 contract. What disappeared was the scaffolding
around them.

## Layout

- `agent/models.yml` - the `sol` provider serving `gpt-5.6-sol` (key via `SOL_API_KEY` env, no secret in repo).
- `agent/config.yml` - role routing (all roles on gpt-5.6-sol), approvals, skills dirs.
- `agent/extensions/dotfiles-harness.ts` - the ported gates + Slack notifier.
- `install.d/66-omp.sh` links these into `~/.omp/agent/` and runs the Herdr integration.

## Documented gaps to verify in a real run

These are places omp's public docs did not fully pin down. The code makes a
best-effort choice and comments it; confirm on your machine before trusting it
beyond the trial.

1. **Root vs subagent discriminator.** omp exposes no guaranteed flag. The Slack
   "finished" notice keys off `session_stop`, which is documented to fire for root
   sessions only. Verify subagents do not page you.
2. **System-prompt injection.** omp has no per-request system-prompt hook, so the
   scope brief is delivered as a `steer` message at `turn_start` instead of being
   injected into the system prompt. Behavioral difference from opencode, not a bug.
3. **`tool_result` patch shape.** The comment self-check appends its reminder to
   the tool result's content array; confirm the reminder actually reaches the model.
4. **Global `APPEND_SYSTEM.md`.** The rules are linked to `~/.omp/agent/APPEND_SYSTEM.md`;
   confirm omp reads a global one (it definitely reads project `.omp/APPEND_SYSTEM.md`).
5. **Herdr min version.** `herdr integration install omp` needs contract v3; run
   `herdr integration status` to confirm `omp: current (v3)`.

Canary takeover is intentionally not ported - it is coupled to the checkpoint flow
and maturity-data sync. Add it once the trial proves the rest is worth keeping.

## Try it in your real environment

```sh
# 1. Install + link (on your Mac/Ona, where Herdr lives)
export OMP_EXPERIMENT=1
export SOL_API_KEY=...            # your gpt-5.6-sol key; adjust baseUrl in models.yml if you use a gateway
./install.sh                      # runs install_omp + setup_omp_config + install_herdr_omp_integration

# 2. Sanity-check config discovery
omp models                        # should list sol/gpt-5.6-sol
herdr integration status          # should show omp: current (v3)

# 3. Run it in a Herdr pane and confirm it shows as an `omp` agent, not a plain shell
omp
```

Disable at any time by unsetting `OMP_EXPERIMENT` and re-running `install.sh`; the
opencode setup is untouched throughout.
