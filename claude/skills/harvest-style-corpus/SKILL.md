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

   Preserve every recoverable PR revision chain before curating it:

       ~/dotfiles/claude/pr-style/eval/harvest.sh sync-descriptions 500

   This writes structured evidence under
   `$STYLE_HARNESS_DATA/pr-style/corpus/authoring/revisions/`. It records the earliest and last
   author revisions separately from the current body because bots can edit the body after the
   author's final revision. Agent authorship remains `unverified` unless another source proves it.

2. For each promising **cleanup commit**, pull the diff and judge it against `../../pr-authoring.md`:

       gh api repos/VantaInc/obsidian/commits/<sha> --jq '.files[]|select(.patch!=null)|"\(.filename)\n\(.patch)"'

   Keep only diffs that are genuine comment/test cleanup (a real rule from the guide: restated
   comment, non-evergreen ref, library-agreement test, single-use helper). Skip pure code refactors.

3. For each promising **description** PR, dump its history and pick a *consecutive* revision pair
   where a named tell flipped (formula opener, diff narration, em-dash pileup) - not just first-vs-last:

       ~/dotfiles/claude/pr-style/eval/extract-pr-description-history.sh <pr>

4. Write each new example into the corpus, matching the existing format:
   - comments/tests -> append to `$STYLE_HARNESS_DATA/pr-style/corpus/simplify/human/cleanup-examples.md`
     (BEFORE / AFTER / rule + commit, exactly like the entries there).
   - descriptions -> append to `.../simplify/human/description-pairs.md` as numbered `BEFORE` /
     `AFTER` examples plus the tell fixed. Use consecutive author revisions where the style tell
     flips; raw first/final evidence remains in `authoring/revisions/`.
   - Dedupe against what's already there (check the commit SHA / PR number).

5. Update `$STYLE_HARNESS_DATA/pr-style/corpus/SOURCES.md` with the new PR numbers / SHAs so the
   corpus stays auditable.

6. If asked to commit, inspect status and diff, then stage only the intended corpus and result paths.
   Do not use `git add -A` in this intentionally dirty data workspace. Only push if I ask.

## After harvesting

Offer to re-run the calibration so I see whether the new examples move recall (a drop flags a
fresh rubric blind spot):

    ~/dotfiles/claude/pr-style/eval/run-eval.sh simplify-calibrate

Run `description-calibrate` after changing PR-description pairs.

For docs, the corpus is Google Docs, not git - harvesting there is manual: I hand you a new doc,
you add it under `$STYLE_HARNESS_DATA/doc-style/corpus/`. This skill covers the PR flows.
