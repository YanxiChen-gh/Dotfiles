# Doc Authoring & Planning Artifacts

## Doc authoring

When writing a design doc, RFC, spec, runbook, or playbook, use a doc-authoring workflow/skill if your tool has one and follow `~/dotfiles/claude/doc-style/rubric.md` (the local `.md` is typically `gsync`'d to a Google Doc afterwards). Same throughline as PR authoring: thesis first, fence the scope, receipts not claims, one load-bearing frame, and a ruthless draft-then-cut pass - the failure mode is bloat and a buried point, not word choice.

## Planning artifacts

For any plan, design doc, or pre-implementation review artifact (plan mode included), default to a **Lavish HTML artifact** to open and annotate in the browser, not a plain markdown file - make it rich (sections, diagrams, comparisons, decision inputs). Open it with `open-lavish <file>` and give the user the single verified URL that command returns; it owns Lavish startup and browser exposure for the current environment. Use `lavish-axi-safe poll <file>` and `lavish-axi-safe end <file>` for follow-up commands so a server start or version upgrade retains the same host-safe configuration. Fall back to markdown only when Lavish is unavailable or it's a throwaway one-liner.
