# omp (oh-my-pi) harness

A parallel harness that runs the same gates as the opencode setup, on
[oh-my-pi](https://github.com/can1357/oh-my-pi) instead of opencode. It
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
- `install.d/66-omp.sh` links these into `~/.omp/agent/`, hides thinking blocks,
  enables extended context, and selects `openai-codex/gpt-6.1-sol` via ChatGPT
  OAuth. It resets any existing `enabledModels` allow-list so omp's full built-in
  catalog remains available. The catalog includes both `openai/gpt-6.1-sol`
  and `openai-codex/gpt-6.1-sol` in omp 18.4.4 or newer.
  The module then runs the Herdr integration, registers RTK (best-effort),
  and syncs the Glean MCP overlay.
  `extendedContext` is a global OMP setting, not a Codex-only setting. It raises
  supported models to their provider's extended limit and may cost more.
  Codex GPT-5.6 Sol/Terra have 1M-token windows, GPT-6 Sol currently reports
  872K input tokens, and GPT-6.1 Sol supports up to 922K when available.
  Forcing 1M on the GPT-6 Codex endpoints could exceed their actual limits.

## Available models

Omp discovers its model catalog natively. For model selection, the installer sets
`modelRoles.default` and clears a previous `enabledModels` restriction; it does
not maintain a separate model list. Codex models require `/login openai-codex`;
OpenAI API models require `OPENAI_API_KEY`. This is startup selection, not
request-time failover. The installer leaves `disabledProviders` untouched to
preserve global and path-scoped preferences.

## OpenAI harness defaults

The installer selects `apply_patch` for every `openai/` and `openai-codex/`
model. It prepends those provider patterns to `edit.modelVariants` because OMP
uses the first matching substring, preserving the other stored mappings and
the global edit mode for other providers.

`providers.openai-codex.codeMode` is set to `auto`. Models advertising
`code_mode_only` route most tool calls through Eval; other Codex models retain
direct tools. This setting does not activate Code Mode for the `openai` API
provider. The underlying OMP tools remain available through the Eval bridge.

Run `configure_omp_defaults` from `install.d/66-omp.sh` to sync only these OMP
defaults without rerunning the full installer. Start a new session after syncing.

## Comparison with the opencode setup

The opencode integration, mapped to its omp equivalent:

| opencode | omp |
| --- | --- |
| Model + agents | `openai-codex/gpt-6.1-sol` via ChatGPT OAuth by default; the full omp model catalog is available |
| Auto mode (`--auto` wrapper) | Native `yolo` default |
| Scope / verify / PR / comment gates | ported in `dotfiles-harness.ts` (same scripts) |
| Slack attention notifications | ported in `dotfiles-harness.ts` |
| Herdr session/subagent/state sync | native `herdr integration install omp`; workspace title mirrored by the harness |
| Same-session checkpoint/compaction | native auto-compaction |
| Global rules (`AGENTS.md`) | `APPEND_SYSTEM.md` (linked) |
| Skills: `~/.claude/skills` + `~/.agents/skills` (shared, advisor, agent-maturity, Obsidian AI Platform) | **native** - omp's Claude + Agents providers read the same dirs |
| Glean MCP overlay | native merge from `omp/mcp-servers-work.json` on work machines; exact managed entry removal from default and named profiles on personal machines |
| RTK token-optimized shell output | `rtk init --agent omp` (best-effort; may be unsupported) |
| Herdr workflow launch (`prefix+a`) | omp by default; `OMP_EXPERIMENT=0` selects OpenCode |
| `opencode-claude-auth` (Anthropic SSO) | Native setup and `/login` |
| Canary takeover | deferred (checkpoint/maturity-coupled) |
| `vanta-doc-discovery` work Glean adapter | **supported** - uses the active runtime's mounted Glean search and document-read tools; OpenCode aliases remain client-conditional |
| `tui.jsonc` | not ported (cosmetic TUI prefs) |

The skills row is the important one: omp discovers `~/.claude/skills` and
`~/.agents/skills` natively. The installer links shared, advisor, agent-maturity,
and Obsidian AI Platform skills there and refuses to mark omp ready when its
required maturity scripts or shared scope and outcome skills are missing.
The native Agent Hub owns subagent detail. Herdr remains the cross-workspace
lifecycle view and does not duplicate omp's task list.

Lavish feedback mode is `managed-async` in a human-interactive omp TUI. Run
each safe poll as one managed async Bash job per feedback round. While a
Lavish review is active, the harness blocks `ask` for that OMP session so the
managed poll remains the only approval channel. Explicit end, Send & End, or
process shutdown clears the guard; normal turn settlement does not.

The opener emits a Herdr review-ready notification with the verified URL and a
request sound. OMP also shows an in-app readiness notice. The harness reminds the
model to share the returned URL in chat with a natural review handoff before it
waits; it does not enforce a message template or notify on every poll. Failed
URL verification does not announce readiness, and notification failure does not
discard a usable URL.

On work machines, `auth-vanta-agents` reports OMP Glean and `slack-vanta`
status without reading credential payloads. Run it yourself in a private
terminal to repair missing auth; agents may run only `auth-vanta-agents --status`.

## Operational notes

The trial exercised standard OpenAI requests, gate loading, managed Lavish jobs,
Herdr title sync, multiline prompts, and Agent Hub behavior. Keep these lifecycle
details in mind when troubleshooting:

1. Slack completion uses omp's root-only `session_stop`; task agents do not emit it.
2. Global rules are linked at `~/.omp/agent/APPEND_SYSTEM.md`.
3. Run `herdr integration status` after Herdr upgrades and confirm `omp: current`.

Global instructions route code, unit tests, comments, and PR descriptions to the shared
[PR style guide](../agent-rules/guides/pr-authoring.md) for both authoring and review, with a check before
handoff. The cleanup skill, evaluation harness, and comment reminder use that same standard.
Review requests also load the separate [review voice](../agent-rules/guides/review-tone.md). Historical
examples remain manual evaluation references, not few-shot inputs for the agent.

Herdr owns completion toasts for root OMP sessions with a Herdr pane and socket.
The harness overrides `completion.notify` to `off` in memory so OMP's
session-title / `Complete` toast does not duplicate Herdr's `OMP finished` toast.
Standalone and nested OMP sessions retain their configured completion policy.
Ask/error notifications and Slack notifications are unchanged, and the override
does not write global or project configuration. Reload the harness or start a new
OMP session to apply extension changes.

PR-readiness handoffs follow the shared
[verification and handoff rule](../agent-rules/verification-and-handoff.md):
announce a successful PR push before readiness, then use the existing `babysit-pr`
workflow through finite managed async polling rounds. OMP can yield the progress
response and resume when a job result arrives. Keep the session open until the
readiness or blocker update; this is session-owned monitoring, not a durable daemon.
Push-only requests do not start babysitting, and monitoring does not expand permissions.

Canary takeover is intentionally not ported - it is coupled to the checkpoint flow
and maturity-data sync. Add it once the trial proves the rest is worth keeping.

## Try it in your real environment

```sh
# 1. Install + link (on your Mac/Ona, where Herdr lives)
./install.sh                      # runs install_omp + setup_omp_config + install_herdr_omp_integration

# 2. Authenticate privately, then start omp with the configured Codex model.
# A fresh interactive install opens onboarding before any model request.
# If not authenticated, run /login openai-codex inside omp, then restart it.
omp
herdr integration status          # should show omp: current (v3)

# 3. Run it in a Herdr pane and confirm it shows as an `omp` agent, not a plain shell
omp
```

The whole workflow follows the default: `prefix+a` / `prefix+shift+a` launch omp,
and the `--select` picker offers omp. If omp is unavailable or its integration
setup is incomplete, the launcher falls back to OpenCode. Set
`HERDR_AGENT_CMD=opencode` (or `omp`) in the environment
before starting Herdr to override its server-wide default.

When seeding an initial prompt via `prefix+a --select`, the launcher passes omp a
mode-600 temporary `@file` argument. OpenCode receives its native `--prompt`
argument. Both agents consume the prompt during startup, so the workflow does
not depend on a guessed ready string or delay.
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
