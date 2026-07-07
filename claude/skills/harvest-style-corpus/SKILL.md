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
2. **PR descriptions** - GitHub body edit history (`userContentEdits`; before = an earlier
   revision, after = the merged body). Not in git; only edits I made on GitHub post-creation.

## Procedure

1. Surface candidates:

       ~/dotfiles/claude/pr-style/eval/harvest.sh both 20

   This prints cleanup-commit candidates and PRs with multiple body revisions. It does NOT write
   anything.

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
   - descriptions -> append to `.../simplify/human/description-pairs.md` (rev-before / rev-after +
     the tell fixed).
   - Dedupe against what's already there (check the commit SHA / PR number).

5. Update `$STYLE_HARNESS_DATA/pr-style/corpus/SOURCES.md` with the new PR numbers / SHAs so the
   corpus stays auditable.

6. Commit the data repo (it's private): `git -C "$STYLE_HARNESS_DATA" add -A && git -C "$STYLE_HARNESS_DATA" commit -m "harvest: <what>"`. Only push if I ask.

## After harvesting

Offer to re-run the calibration so I see whether the new examples move recall (a drop flags a
fresh rubric blind spot):

    ~/dotfiles/claude/pr-style/eval/run-eval.sh simplify-calibrate

For docs, the corpus is Google Docs, not git - harvesting there is manual: I hand you a new doc,
you add it under `$STYLE_HARNESS_DATA/doc-style/corpus/`. This skill covers the PR flows.
