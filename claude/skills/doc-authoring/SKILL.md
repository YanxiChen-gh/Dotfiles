---
name: doc-authoring
description: Write design docs, RFCs, specs, runbooks, and playbooks in Yanxi's style - the local .md later synced to a Google Doc via gsync. Use when asked to write, draft, or restructure any such doc. Loads the style rubric, links exemplars, and enforces a draft-then-cut pass. Not for PR descriptions (use the pr-authoring guide / simplify-pr) or code comments.
---

# Doc Authoring

You are writing a doc that reads like Yanxi wrote it. The failure mode is not bad words - it's
bloat, hedging, and a missing point. Fight those.

## Before drafting

Read the rubric and apply it - don't reproduce it from memory, it's the source of truth and may
have changed:

    ~/dotfiles/claude/doc-style/rubric.md

Then skim 1-2 exemplars for the doc type, if the private data repo is cloned (default
`~/style-harness-data`; else skip - the rubric is enough). Under
`$STYLE_HARNESS_DATA/doc-style/corpus/human/`:
- Design/scoping: `03-agent-onboarding.md` · Technical proposal: `04-online-evaluators.md`
- RFC: `05-app-hosting-rfc.md` · Spec with verification: `06-dataset-mgmt-v0.md`
- Runbook/playbook: `01-day1-playbook.md`

Read for stance and structure, not to copy content.

## While drafting

- First sentence of every section is the point, as a claim or imperative. No warm-up.
- State what this does NOT do. Fence the scope (Non-Goals / "does not promise").
- For every real decision: name the alternative and why it lost.
- Concrete details must be receipts (real IDs, endpoints, dates you actually observed), not a
  decorative catalog. If you didn't verify it, don't dress it up as if you did.
- One load-bearing frame. Reuse it; don't pile on analogies.
- Write like a person: first person where natural, honest about what's unresolved.

## After the first draft - the cut pass (do not skip)

This is where agent docs go wrong. Re-read and:
1. Delete any section that exists for completeness, not need: glossary, checklist, quick-reference,
   generic "anti-patterns" / "gotchas". If the reader didn't ask for it, cut it.
2. Find anything said more than once (body + reference + checklist). Keep one instance.
3. Delete every sentence removable with no loss - especially hedged openers.
4. Check every number traces to something real. Vague-true beats specific-false.

Target: if you can say it in a quarter of the words, do. The human twin of a 3,646-word agent doc
was 909 words with the same payload.

## Before handoff / gsync

Offer to review the draft against the rubric and return a ranked fix list
(`~/dotfiles/claude/doc-style/reviewer.md`), then apply fixes before syncing.
