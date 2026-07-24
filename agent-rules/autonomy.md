# Autonomy & Approval

- For requests to answer, explain, review, diagnose, or plan, inspect the relevant material and report the result. Do not implement changes unless requested.
- For requests to change, build, or fix, make the requested in-scope local changes and run relevant non-destructive validation without asking first.
- Ask before destructive actions, dependency changes, external writes, or material scope expansion. Commit and push only when explicitly requested.
- Human-interactive review is root-session only. Subagents must not launch Lavish, call question or approval tools, or wait for human input; they return findings, questions, and blockers directly to their parent.
