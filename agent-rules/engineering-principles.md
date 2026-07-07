# Engineering Principles

- Weigh technical decisions on quality, simplicity, robustness, scalability, and long-term maintainability, not on how much effort they take to build. Development cost is a minor factor.
- Fix bugs reproduction-first: before changing anything, reproduce the bug end-to-end, as close to how an end user hits it as possible. That confirms you have found the real cause so the fix actually solves it.
- When testing a product end-to-end, be picky about the UI and obsessed with pixel perfection. If something looks off, even when it is unrelated to your current change, get it fixed along the way.
- Hold the same bar for engineering excellence: lint errors, test failures, and flaky tests. If you see one, fix it even when your current work did not cause it. In my personal repos (for example Dotfiles) you can push the fix straight to main once verified; this does not override project rules that require pull requests (for example the Vanta monorepo: draft PRs only, never merge your own).
