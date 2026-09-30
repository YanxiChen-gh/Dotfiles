# Verification & PR Handoff

Choose the narrowest verification that proves the changed behavior. Exercise a real runtime path when unit checks cannot establish the user-visible, integration, or operational result. Report commands, observed results, and known gaps accurately.

Before opening a PR, include only verification that gives a reviewer confidence beyond routine CI. Use an independent review for high-risk, cross-domain, or behaviorally hard-to-exercise changes. The deterministic `verify-gate` hook checks that a work-repository PR includes reviewer-useful evidence.

After a successful authorized PR push, promptly tell the user the PR URL, pushed commit, and what verification or CI/review work remains. This is a progress update, not a claim that the PR is ready.

When the requested outcome includes PR readiness or explicit babysitting, continue with the existing `babysit-pr` skill after the push. Prefer managed background monitoring so the user can inspect the PR or continue the conversation while CI and reviews run. Follow the skill's bounded stop condition, investigate in-scope findings within existing permissions, and report readiness or a concrete blocker when monitoring ends. A request only to commit or push does not authorize babysitting. Monitoring does not authorize additional pushes, comments, merges, deployments, or other external actions.

In OMP, use finite polling rounds through managed Bash with `async: true`, respecting the skill's polling cadence and retaining its state file and event cursor. Yield a progress response while a polling round is pending; delivered results resume monitoring in the same session. Process results and schedule the next round while monitoring remains active; do not treat an indefinitely running watch command as an event-driven monitor. Keep approval decisions in the root session and report meaningful status changes rather than every poll. Background monitoring requires the OMP session to remain open; it does not survive session shutdown. If managed async execution is unavailable, monitor in the foreground and say so.
