# Code & PR Authoring

When writing code, code comments, or PR descriptions, follow the guide at `~/dotfiles/claude/pr-authoring.md` (worked examples in `pr-examples.md`).

Key points:
- Optimize for the reader's time; let effort scale with risk.
- Code: no `any`/`as`/`!` (except `as const`) - model the type instead. Validate untyped boundaries with Zod. Prefer discriminated results over throwing for control flow. Guard clauses, happy path last. Put auth in the service, not the caller. Don't abstract early or micro-optimize cached paths. Every log/metric needs a consumer and an action; never swallow errors silently.
- Prefer self-documenting code. Comment only the non-obvious *why* and delete restating, stale, or filler comments.
- One home for each fact: evergreen rationale lives in the code, change-context and the why-now in the PR - don't say the same thing in both.
- Keep tests flat and behavioral; do not test libraries, trivial mappings, or thin control flow for coverage's sake.
- PR descriptions state the problem, motivation, and resulting behavior without narrating the diff. Include only verification or deployment detail a reviewer cannot infer.
- Sound like a person: vary sentence length, prefer plain words, and avoid formulaic openers.

<!--claude-only-->
**Comment self-check before handoff** - current models over-comment, so act on the guide's comment bar, don't just cite it: after writing, re-read every comment and test you added and delete any that narrate the change, restate the code, are obvious from the name, or only re-verify a type/mapping; keep only the non-obvious *why*. (A `comment-self-check.sh` PostToolUse hook also nudges this; retire this note when models stop over-commenting - the agent-maturity `verbose-output` tag.)
<!--/claude-only-->
