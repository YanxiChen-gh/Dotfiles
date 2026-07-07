# Doc Style Rubric (Yanxi)

Single source of truth for how docs should read. Drives three things: the authoring skill
(`SKILL.md`), the pre-sync reviewer (`reviewer.md`), and the eval judge (`eval/judge.md`).
Change the style here and everything downstream follows.

Scope: design docs, RFCs, specs, runbooks, playbooks - the local `.md` you later `gsync` to a
Google Doc. Not PR descriptions (see `../pr-style/`).

## The finding this encodes

Agent docs and my docs on the *same topic* differ in structure and stance, not vocabulary. The
agent doesn't say "delve" or "seamless" - it says everything three times, appends a glossary
nobody asked for, and buries the point in a hedge. So this rubric polices **structure and
stance**. Do not add a word-blacklist; I use "robust", em-dashes, and semicolons freely.

Ground truth: the agent's Day-1 playbook was 3,646 words; mine was 909 for the same payload.

## Signature moves (reward these)

Each has a checkable question. A doc should hit most of these; a doc that hits none is not mine.

1. **Thesis first, bluntly.** The point is the first sentence of the section, stated as a claim
   or an imperative, not eased into.
   - Check: does each section's first sentence commit to something? ("Do not require per-surface
     suites for MVP." not "There are a few considerations around suites...")
2. **Fence the scope.** State what this does NOT do, explicitly.
   - Check: is there a Non-Goals / "does not promise" / "V0 does not solve X" statement?
3. **Alternatives + why-not.** Show the roads not taken and the reason each was rejected.
   - Check: for any real decision, is there an alternative named and a reason it lost?
4. **Justify the decision not to act.** Deferring is a decision; say why.
   - Check: are deferrals reasoned ("holding off on purpose: keeps a code-review gate"), not just
     listed as "later"?
5. **Receipts, not claims.** Concreteness is evidence you ran it: real IDs, endpoints, HTTP
   codes, dates - not a catalog of file paths.
   - Check: do the concrete details prove something was verified ("POST /<endpoint> returned 200 on
     2026-05-01"), or are they just decoration?
6. **One load-bearing frame.** A single metaphor or model carries the argument ("the registry is
   the seam", "two-way-door decision").
   - Check: is there one frame doing work, reused - not a pile of unrelated analogies?
7. **A person wrote this.** First person where natural, honest about mess, opinionated.
   - Check: any "it's been a rabbit hole", honest "TBD", a real opinion, or is it voiceless?

## Anti-tells (penalize these - these are what mark a doc as agent-written)

1. **Completeness compulsion.** Auto-appended Anti-patterns / Gotchas / Quick Reference /
   Checklist / Glossary sections that exist for symmetry, not because a reader needs them.
   - Ground truth: my comment on such a section was literally "don't need this section."
   - Check: is any section there only to make the outline feel complete? Cut it.
2. **Triple-coverage.** The same command / term / step stated in the body, then re-listed in a
   reference block, then again in a checklist.
   - Check: is anything said more than once across sections? Say it once.
3. **False precision.** A specific number with no source, especially replacing a vaguer true one.
   - Ground truth: the agent wrote "15,000+ customers" where I wrote "thousands of customers".
   - Check: every number traceable to something real? If invented, delete or vague it out.
4. **Buried thesis / hedged opener.** The point arrives in sentence three behind qualifiers.
   - Ground truth: my comment was "this wording is weird. just say that... don't treat it as an
     afterthought."
   - Check: could the first sentence be deleted with no loss? Then it was a warm-up. Cut it.
5. **Voiceless neutrality.** Encyclopedic, no first person, no opinion, no admission of mess.
6. **Catalog without receipts.** Lots of file paths and commands, zero evidence any of it ran.
7. **Formatting outruns content.** More tables/bullets/bold than novel claims; tables that
   re-tabulate prose already written.
   - Check: does each table carry something prose can't (Scenario/Expected/Observed, Pros/Cons)?
     If it just reformats a paragraph, drop it.

## Contrastive pairs (the teaching signal)

Seeded from real edits. Left = agent draft, right = the fix, tagged with the anti-tell.

| Anti-tell | Agent wrote | Fix |
|---|---|---|
| False precision | "goes stale quickly across 15,000+ customers" | "goes stale quickly across thousands of customers" |
| Buried thesis | "You don't have production traffic yet, but the choices you make now decide whether evaluation is easy or painful later. The North Star doc assumes you already have data; this section is what to do before that." | "Start setting up online evals from day 1 - that's your playground for iterating as you ship. Don't treat it as an afterthought." |
| Completeness compulsion | appended "Appendix: glossary", "Day-1 checklist", "Quick reference", "Gotchas & known traps" | none of these - the reader didn't need them |
| Triple-coverage | commands in body + Quick Reference + checklist | commands stated once, where the step is |

Add new rows whenever a review catches a fresh instance. This table is also the judge's
calibration set: a correct judge, shown the left column blind, flags the right anti-tell.

## Scoring (for the judge and reviewer)

Score a doc 0-2 per signature move (0 absent, 1 partial, 2 clearly present) and 0-2 per anti-tell
(0 clearly present/bad, 2 absent/clean). Report the per-criterion scores, not just a total - the
value is in *which* criterion failed and the specific line that failed it.
