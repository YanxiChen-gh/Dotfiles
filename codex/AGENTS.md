# Codex Global Instructions

## Code & PR Authoring

When writing code, code comments, or PR descriptions, follow the guide at `~/dotfiles/claude/pr-authoring.md`.

Key points:
- Optimize for the reader's time; let effort scale with risk.
- Code: no `any`/`as`/`!` (except `as const`) — model the type instead. Validate untyped boundaries with Zod. Prefer discriminated results over throwing for control flow. Guard clauses, happy path last. Put auth in the service, not the caller. Don't abstract early or micro-optimize cached paths. Every log/metric needs a consumer and an action; never swallow errors silently.
- Comments and tests are where sloppiness hides — hold them to the same bar as code, not nice-to-haves.
- Comments: prefer self-documenting code; comment only the non-obvious *why* (a load-bearing comment can be long); delete restating/stale/AI-filler comments.
- One home for each fact: evergreen rationale lives in the code, change-context and the why-now in the PR — don't say the same thing in both.
- Tests: don't test for coverage's sake — no tests of libraries, trivial mappings, or thin control flow. A complex or heavily-mocked test is a red flag at the code or the test; inject deps instead of `as never`/`as any`. Keep tests flat and behavioral.
- Descriptions are concise and high-level: before → problem → after, no diff narration. Scale to the change and trust the diff — for a simple change the whole Changes section is often one line ("refactor X to Y so that Z") or TIN; spend words only on what the diff can't show. Use a decision table for remove/replace/migrate; delete inapplicable template sections rather than leaving them empty.
- Motivation is one or two sentences stating the root cause/tradeoff. Testing shows only the hard stuff as evidence (e2e, manual, reproducible command); skip the obvious. Deployment states blast radius when it matters.
- Sound like a person, not AI: vary sentence length and break up run-ons, plain words over exhaustive jargon, no formula openers ("One behavior change a reviewer can't see…"), go easy on em-dashes/colons.

## PR Review Tone

When leaving PR comments, reviews, or code feedback, follow the tone guide at `~/dotfiles/claude/review-tone.md`.

Key points:
- Concise and direct — no fluff
- Lowercase "lgtm" for approvals, brief or empty body
- Questions over commands: "Should this be X?" not "Change this to X"
- Curious not prescriptive: "Curious what case did you hit?" / "Hmm why is this needed?"
- End concerns with "What do you think?"
- Don't leave verbose summaries, empty praise, or overly formal language

## Writing Style

Never use the em dash ("—"). Use a plain hyphen ("-") instead. This applies to everything you write on my behalf: chat responses, code, code comments, commit messages, PR descriptions, and docs.

## Git & Generated Files

- Never add yourself (the AI agent) as a commit co-author. Do not append `Co-Authored-By:` trailers naming Claude, Codex, Cursor, or any agent, and do not add agent attribution to commit messages or PR descriptions unless I explicitly ask.
- Never hand-edit `CHANGELOG.md` files or any file marked as auto-generated (generated-header banners, lockfiles, codegen output, build artifacts). Change the source and regenerate instead.

## Engineering Principles

- Weigh technical decisions on quality, simplicity, robustness, scalability, and long-term maintainability, not on how much effort they take to build. Development cost is a minor factor.
- Fix bugs reproduction-first: before changing anything, reproduce the bug end-to-end, as close to how an end user hits it as possible. That confirms you have found the real cause so the fix actually solves it.
- When testing a product end-to-end, be picky about the UI and obsessed with pixel perfection. If something looks off, even when it is unrelated to your current change, get it fixed along the way.
- Hold the same bar for engineering excellence: lint errors, test failures, and flaky tests. If you see one, fix it even when your current work did not cause it. In my personal repos (for example Dotfiles) you can push the fix straight to main once verified; this does not override project rules that require pull requests (for example the Vanta monorepo: draft PRs only, never merge your own).

@RTK.md
