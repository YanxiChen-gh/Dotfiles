# Yanxi's PR Authoring Guide

How to write PR descriptions and code comments on behalf of Yanxi. Optimize for the
reader's time: say what they need to understand the change, and nothing they can already
read from the diff. This complements a repo's PR template — fill the required sections,
just keep each one tight.

## PR Descriptions

Concise and high-level. Describe the *shape* of the change, not a line-by-line tour.

- **Frame it as before → problem → after.** What the world looked like before, what was
  wrong with it, and what it looks like after — all at a high level.
- **Don't narrate the diff.** The reviewer can read what each file does. Don't list
  "changed X, added Y, updated Z" or walk through the change file by file.
- **Stay at high altitude.** Describe intent and outcome, not mechanics.

Example:
> Before, alarms were keyed by raw string IDs, so a renamed rule silently matched nothing.
> This makes keys structural so a rename is a type error instead of a silent miss.

## Motivation

Keep it short — one or two sentences on why the change is worth making. Don't restate the
description.

## Testing

Only call out tests that took real effort or that a reviewer can't safely assume.

- **Skip the obvious.** Don't mention unit tests, type checks, or lint — they're table
  stakes and CI already proves them.
- **Mention the hard stuff.** E2E tests, manual testing steps, edge cases verified by hand,
  staging walkthroughs. Say what you actually did so a reviewer knows what's covered without
  re-doing it.
- If there's genuinely nothing beyond the obvious, one short line is fine — don't pad it.

## Code Comments

Comments in code should be evergreen. If an observation only makes sense in the context of
*this change*, it belongs in the PR, not the code.

- **Concise.** A comment earns its place by explaining something the code can't say itself.
- **Remove useless or quickly-stale comments.** Comments that restate what the code does, or
  that narrate the change ("we used to do X", "this is now different because…"), go stale the
  moment the next change lands and just get in the way of readability.
- **Change-context belongs in the PR, not the code.** Those before/after observations make a
  lot of sense as PR description text or inline PR review comments — put them there instead.
- **Keep evergreen *why*.** Comments that explain non-obvious rationale (why it's done this
  way, a gotcha, a link to context) are worth keeping. Comments that explain *what* the code
  does usually aren't.
