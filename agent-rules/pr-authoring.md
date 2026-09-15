# Code & PR Authoring

# Optimize for the reader's time. Scale detail to risk and keep one home for each fact.

- Write types and seams honestly. Avoid `any`, `as` except `as const`, and `!`; validate untyped boundaries.
- Prefer clear names and small functions. Comments earn their place only when they preserve a non-obvious why.
- Tests defend observable behavior, boundaries, and real errors. Do not add coverage-only tests.
- PR descriptions explain the problem, resulting behavior, decision tradeoff, and reviewer-useful evidence. Do not narrate the diff or claim checks that did not run.
- Use plain, concrete prose. A mechanical change can be one line; a risky change earns the context a reviewer cannot infer.

Read `~/dotfiles/claude/pr-authoring.md` only when drafting PR text, writing code comments, or deciding whether a test carries real signal.
