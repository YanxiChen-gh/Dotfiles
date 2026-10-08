# Artifact Presentation & Review

For a design doc, RFC, spec, runbook, or playbook, use the relevant authoring workflow and follow `~/dotfiles/claude/doc-style/rubric.md`.

Use the `plannotator` skill as the default presentation and review layer for artifacts you produce or need me to inspect, including code, documents, plans, reports, diagrams, and other outputs. Choose the content, format, and presentation that best help me understand the work and give useful feedback. Reuse existing artifacts and native rendering when they fit; use richer or custom presentation when it adds value. Keep simple answers and routine status updates in chat.

Automatic plan-review hooks are not installed by this setup; open presentations explicitly rather than assuming plan exit will open them. For CLI sessions, use `plannotator-safe` and an explicit free `PLANNOTATOR_PORT`. Before sharing the URL, run `~/dotfiles/scripts/expose-port.sh <port>` to verify it. Keep presentation and feedback private unless I explicitly request sharing or publication.

When a review is ready, share its verified URL in chat with a brief, natural handoff: what is ready and what input would help. Receive and address feedback in the same agent session; reopen the updated artifact when another review is useful. Do not create a second question or approval surface while waiting for the review.
