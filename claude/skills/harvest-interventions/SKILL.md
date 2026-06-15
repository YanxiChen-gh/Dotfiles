---
name: harvest-interventions
description: Reconstruct the agent-maturity intervention log from artifacts (Claude Code session transcripts, git history, PR review cycles) instead of logging by hand. Use only when explicitly invoked (e.g. "/harvest-interventions", "backfill my intervention log", "harvest interventions for the last 2 weeks", "populate the maturity log automatically"). Pairs with /maturity-review — run this first to give it data.
disable-model-invocation: true
---

# Harvest Interventions

Make Phase 1 of the maturity system zero-effort: instead of running `li` in the moment every
time you step in, a subagent mines the artifacts you already produce and proposes intervention
log entries. You glance, confirm, and it writes them. Backfills the past immediately — no
two-week wait.

**This is approximate, and that's fine.** It reconstructs from evidence, so it will miss
interventions that left no trace (a hand-edit in your editor with no agent session) and may
mis-bucket a few. The human-confirm step is the accuracy gate; the goal is a good-enough
baseline at ~10× less effort than moment-logging, not a perfect ledger. `li` stays the
escape hatch for things artifacts can't see.

## Inputs

- **Repo** — default: the current repo (`git rev-parse --show-toplevel | xargs basename`).
  Ask if the user named several; harvest one at a time so the confirm step stays legible.
- **Window** — default: last 14 days. Honor an explicit range if given.
- Target log: `~/dotfiles/claude/agent-maturity/interventions.jsonl`.

## Procedure

### 0. Refresh cross-env evidence if stale

Work happens across many ephemeral Ona envs, so the local `~/.claude/projects/` is only a
slice. Before mining, check the evidence freshness:

- Read `~/dotfiles/claude/agent-maturity/evidence/_manifest.txt` → `collected_at`.
- **Run `scripts/collect-ona-evidence.sh` (running-only) if** the manifest is missing, older
  than ~6 hours, or the user passed `--refresh`. Otherwise skip it and say "evidence is fresh
  (collected <when>), skipping collection."
- **Never** run it with `--include-stopped` automatically — that starts stopped envs and costs
  compute. Only do that if the user explicitly asks.
- If collection partially fails (some envs unreachable), proceed with whatever evidence exists;
  note which envs were skipped. Collection is best-effort, not a hard gate.

### 1. Dispatch a mining subagent

Spawn a `general-purpose` subagent (keeps the noisy parsing out of the main context). Give it
the repo, the window, and these instructions verbatim:

> Mine three sources for human interventions on AI-agent coding work in **<repo>** over **<window>**.
> Return ONLY a JSON object — no prose. Be conservative; when unsure, omit.
>
> **A. Claude Code session transcripts** (richest source).
> Read BOTH locations:
>   - this env's live transcripts: `~/.claude/projects/`
>   - transcripts pulled from ALL Ona envs: `~/dotfiles/claude/agent-maturity/evidence/*/projects/`
>     (populated by step 0's collector run, covering work across ephemeral remote envs).
> For each, include the repo's main dir AND any worktree dirs (e.g. `-workspaces-<repo>` and
> `-workspaces-<repo>--claude-worktrees-*`). Parse the `*.jsonl` files modified within the window.
> The same session may appear in more than one location — de-dupe by session filename (the UUID). A **human turn** is a line with
> `type=="user"` whose `message.content` is a plain string, or a list containing `text`
> blocks. **Exclude** turns whose content is `tool_result`, or that are clearly
> harness-injected (wrapped in `<command-name>`, `<command-message>`, `<system-reminder>`,
> `<local-command-stdout>`, or caveat/skill boot text). Walk turns in order and classify each
> genuine human turn *relative to the preceding assistant turn*:
>   - **task** — a fresh task statement / new feature ask → NOT an intervention; count it
>     toward the task denominator only.
>   - **correction** (Trust) — points out a bug, says it's wrong, asks to redo/fix/revert
>     something the agent produced.
>   - **clarification** (Spec) — redirects the approach, adds/restates requirements, answers
>     an agent question with new constraints, "no, I meant X", "use the GraphQL resolver not REST".
>   - **unblock** (Babysit) — restarts a stalled/looping agent, resolves an error or merge
>     conflict for it, "you're stuck, try Y", "continue".
> Also COUNT assistant `AskUserQuestion` tool calls (agent-initiated questions) — report the
> count separately; these are a positive Spec signal, not interventions.
>
> **B. Git history.** On branches with commits in the window: agent commits carry a
> `Co-Authored-By: Claude` trailer. Human commits **without** it that directly follow agent
> commits, or are "fix"/"revert"/"oops" fixups, corroborate **corrections**. Report shas.
>
> **C. PRs** (`gh pr list`/`gh pr view`, author=@me, merged or open in window). Count review
> round-trips / "changes requested" cycles → corroborating **correction** signal. Report PR #s.
>
> Output schema:
> ```json
> {
>   "repo": "<repo>", "window": "<from>..<to>",
>   "task_count": <int>,
>   "agent_initiated_questions": <int>,
>   "proposals": [
>     {"date":"YYYY-MM-DD","type":"correction|clarification|unblock",
>      "note":"<short, what happened>","source":"auto",
>      "evidence":"transcript <id>#turn<N> | commit <sha> | PR #<n>","confidence":"high|med|low"}
>   ]
> }
> ```
> Cap at the clearest ~40 proposals; if you truncated, say so in a `"truncated":true` field.

### 2. Present for confirmation (compact)

From the subagent's JSON, show the user a tight summary — **don't** dump all rows:
- counts by type (correction / clarification / unblock), task_count, agent_initiated_questions
- 2–3 example notes per type
- flag any `low` confidence rows separately

Then ask one question: **write all, prune some, or discard?** Offer "write all" as the default
for the lazy path. If they prune, take the list of indices to drop.

### 3. Write

Append the confirmed proposals to `interventions.jsonl`, one compact JSON line each, preserving
`source:"auto"`, `evidence`, and `confidence`. Don't rewrite or dedup existing lines. Report
how many were written and the resulting per-type totals in the log.

### 4. Hand off

Tell the user the log is populated and to run **`/maturity-review`** next for the evidence-based
baseline. Mention the `agent_initiated_questions` count — it feeds the Spec supporting signal
(agent-initiated question rate) that `/maturity-review` reports.

## Notes

- Re-running over an overlapping window will double-log. Either harvest forward-only (window
  starts after the last harvested date) or tell the user to dedup. Prefer non-overlapping windows.
- Sessions about non-coding work (e.g. building this maturity system itself) aren't product
  interventions — the subagent should skip or down-weight them; the user prunes the rest.
