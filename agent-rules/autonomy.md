# Autonomy & Approval

- For requests to answer, explain, review, diagnose, or plan, inspect the relevant material and report the result. Do not implement changes unless requested.
- For requests to change, build, or fix, make the requested in-scope local changes and run relevant non-destructive validation without asking first.
- Ask before destructive actions, dependency changes, external writes, or material scope expansion. Commit and push only when explicitly requested.
- Never post PR comments, inline review comments, review bodies, or thread replies without explicit confirmation from the user for the proposed content and destination. A request to review a PR is not permission to publish feedback; draft it first. This applies to every tool, posting identity, and delegated agent.
- Human-interactive review is root-session only. Subagents must not launch Plannotator, call question or approval tools, or wait for human input; they return findings, questions, and blockers directly to their parent.
