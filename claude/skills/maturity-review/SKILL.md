---
name: maturity-review
description: Assess Yanxi's agent-autonomy maturity and recommend the single highest-leverage next move. Use only when explicitly invoked (e.g. "/maturity-review", "where am I on the autonomy journey", "score my agent setup", "what should I uplevel next"). A periodic meta-eval of the agent harness itself, not a code task.
disable-model-invocation: true
---

# Maturity Review

A recurring meta-eval of Yanxi's multi-agent setup: score where the harness sits on the
autonomy maturity model, ground it in evidence, recommend the one next move, and update the
tracker. This is the "treat the harness as a product / eval your own setup" discipline made
into a checkpoint — run it roughly monthly or after a meaningful harness change.

The goal being measured is **less human attention per shipped change**. Score outcomes, not
inventory: a capability counts only when it's *load-bearing in the real loop*, not when it
merely exists somewhere.

## Inputs (read these first — don't work from memory)

- `~/dotfiles/claude/agent-maturity/rubric.md` — the model, dimensions, and scoring procedure.
- `~/dotfiles/claude/agent-maturity/tracker.md` — current scorecard, last recommendation, changelog.
- `~/dotfiles/claude/agent-maturity/interventions.jsonl` — raw intervention signal (may be sparse/empty early on; say so rather than inventing a baseline).

## Procedure

1. **Read** the three inputs above.

2. **Gather evidence** (pragmatic — this is signal, not an audit). Prefer cheap reads:
   - Intervention log: counts by `type` over the window since the last review, total cost_min.
   - GitHub, for recent agent-authored PRs (ask which repos if unclear; default to the active one):
     `gh pr list --author "@me" --state merged --limit 30 --json number,title,reviewDecision,createdAt,mergedAt`
     and for a sample, review round-trips / post-handoff force-pushes / time-to-merge as Trust signal.
   - The skills/plugins actually wired into the loop (what gates completion vs what's opt-in).
   If evidence is thin, score provisionally and **say what data would firm it up** — never
   inflate a level on hope.

3. **Score** each dimension L1–L5 per the rubric's procedure. Overall = the weakest dimension.
   For each, cite the specific evidence that pins the level (and the missing criterion that
   blocks the next level).

4. **Compute the north star** — interventions per merged agent-PR (total + per type) — and
   state the trend vs the previous tracker entry. If no baseline, set one.

5. **Ablation check** — look at the previous changelog entry: did that harness change move the
   metric? If not, name it as candidate scaffolding to strip (models improve; don't accrete).

6. **Recommend exactly one next move**: the cheapest lever on the weakest / most-painful
   dimension. **Prefer wiring up an asset Yanxi already owns** over building new — e.g.
   `full-verification-workflow`, `review-pr`, `simplify-pr`, the ai-platform eval skills,
   worktree/background-job orchestration. Name the concrete change and how you'll know it worked.

7. **Update the tracker**: rewrite the scorecard table + "Last reviewed" date, replace the
   "Recommended next move" section, and append a changelog entry (`date — what changed —
   metric impact: TBD`). Leave `interventions.jsonl` alone (that's logged live, not here).

## Output

Keep it tight — a checkpoint, not an essay:

- **Scorecard**: the table (Trust / Spec / Babysit / Overall) with one evidence line each.
- **North star**: the rate + trend (or "baseline set").
- **Ablation**: did the last change pay off? (one line)
- **Next move**: the single recommendation — what, why this one, expected metric effect, how to verify.

Then state plainly that the tracker has been updated.

## Populating the log (remind Yanxi if it's stale)

The scoring is only as good as the raw log. Two ways to fill it — prefer the first:

- **`/harvest-interventions`** (low effort) — a subagent reconstructs interventions from
  session transcripts + git + PR history over a window and proposes entries to confirm. Run
  this if the log looks stale relative to recent agent activity, then re-score.
- **`li` / `log-intervention.sh`** (manual escape hatch) — `li <correction|clarification|unblock>
  "note" [cost_min]`, run from inside the repo. For interventions artifacts can't see (a
  hand-edit with no agent session). `correction→Trust, clarification→Spec, unblock→Babysit`.

If the log is stale, suggest `/harvest-interventions` before scoring rather than scoring thin data.
