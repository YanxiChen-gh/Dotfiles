---
name: harvest-style-corpus
description: Manually harvest new before->after examples from my recent PRs into the style-harness eval corpus. Use when explicitly invoked ("/harvest-style-corpus", "harvest new style examples", "add recent cleanup PRs to the corpus") - when I want to grow the doc-style/pr-style calibration data after shipping more work.
disable-model-invocation: true
---

# Harvest Style Corpus

Grow the calibration corpus from my real work, on demand. The eval only stays honest if the corpus
keeps up with how I actually write - this pulls fresh before->after pairs and curates them in.

The corpus lives in the PRIVATE data repo: `$STYLE_HARNESS_DATA` (default `~/style-harness-data`).
If it isn't cloned, stop and tell me - there's nowhere to write.

## Sources (two, both real)

1. **Comment/test cleanup** - git cleanup commits (before = messy, after = my edit).
2. **PR descriptions** - GitHub body edit history (`userContentEdits`; raw evidence = earliest and
   last author revisions). GitHub retains the body submitted at PR creation, but not drafts edited
   locally before creation. The current body is not an answer key because bots can modify it.

## Procedure

1. Surface candidates:

       ~/dotfiles/claude/pr-style/eval/harvest.sh both 20

   This prints cleanup-commit candidates and PRs with multiple body revisions. It does NOT write
   anything.

   Merge every recoverable complete PR revision chain into the discovery cache before curating it:

       ~/dotfiles/claude/pr-style/eval/harvest.sh sync-descriptions 500

   This refreshes `$STYLE_HARNESS_DATA/pr-style/corpus/authoring/revisions/`. The cache is additive:
   records absent from a later bounded query remain, while returned records are refreshed. The query
   is not treated as a complete inventory. Each written history is complete, or the fetch fails
   before the atomic swap. Agent authorship remains `unverified` unless another source proves it.

2. For each promising **cleanup commit**, pull the diff and judge it against `../../pr-authoring.md`:

       gh api repos/VantaInc/obsidian/commits/<sha> --jq '.files[]|select(.patch!=null)|"\(.filename)\n\(.patch)"'

   Keep only diffs that are genuine comment/test cleanup (a real rule from the guide: restated
   comment, non-evergreen ref, library-agreement test, single-use helper). Skip pure code refactors.

3. For each promising **description** PR, dump its history and pick a *consecutive* revision pair
   where a named tell flipped (formula opener, diff narration, em-dash pileup) - not just first-vs-last:

       ~/dotfiles/claude/pr-style/eval/extract-pr-description-history.sh <pr>

4. Discovery and freezing are separate. For exploratory calibration, write each new example into
   the mutable corpus, matching the existing format:
   - comments/tests -> append to `$STYLE_HARNESS_DATA/pr-style/corpus/simplify/human/cleanup-examples.md`
     (BEFORE / AFTER / rule + commit, exactly like the entries there).
   - descriptions -> append to `.../simplify/human/description-pairs.md` as numbered `BEFORE` /
     `AFTER` examples plus the tell fixed. Use consecutive author revisions where the style tell
      flips; the complete raw chain remains in the discovery cache.
   - Dedupe against what's already there (check the commit SHA / PR number).

5. Update `$STYLE_HARNESS_DATA/pr-style/corpus/SOURCES.md` with the new PR numbers / SHAs so the
   corpus stays auditable.

   For a held-out evaluation, do not point a manifest at the refreshable discovery cache. Review the
   complete history, then explicitly copy each selected raw record into the new append-only version:

       $STYLE_HARNESS_DATA/pr-style/corpus/evidence/pr-description-revisions/<version>/<pr>.json

   `sync-descriptions` must never target that directory. Create a new manifest version whose
   `evidence_path` values name those frozen copies, with exact evidence/body hashes and scoring
   fields. Do not modify an existing frozen manifest or evidence version. Then validate and run it
   offline:

       ~/dotfiles/claude/pr-style/eval/pr-description-benchmark.sh validate <manifest.json>
       ~/dotfiles/claude/pr-style/eval/run-eval.sh description-heldout <manifest.json> --flow simplify
       ~/dotfiles/claude/pr-style/eval/run-eval.sh description-heldout <manifest.json> --flow authoring

   Harvesting discovers source histories. Explicit versioned copies and a manifest freeze the
   selected case set. Materialized output and judgments are evaluation artifacts, not corpus inputs.
   Simplify uses `AGENT_ENGINE` / `AGENT_MODEL` for the candidate and `JUDGE_ENGINE` /
   `JUDGE_MODEL` for Mode C scoring. Authoring is different: the configured agent is the model under
   test and makes each deterministic blind A/B choice with tools disabled. Its prompt and no-tools
   trace are saved per case. Sorted case IDs alternate the preferred revision between A and B so the
   assignment is balanced. Judge settings remain in common metadata for reproducibility but do not
   participate in authoring decisions.

6. If asked to commit, inspect status and diff, then stage only the intended corpus and result paths.
   Do not use `git add -A` in this intentionally dirty data workspace. Only push if I ask.

## After harvesting

Offer to re-run the calibration so I see whether the new examples move recall (a drop flags a
fresh rubric blind spot):

    ~/dotfiles/claude/pr-style/eval/run-eval.sh simplify-calibrate

Run `description-calibrate` after changing PR-description pairs.

For docs, the corpus is Google Docs, not git - harvesting there is manual: I hand you a new doc,
you add it under `$STYLE_HARNESS_DATA/doc-style/corpus/`. This skill covers the PR flows.
