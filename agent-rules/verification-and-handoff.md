# Verification & PR Handoff

Choose the narrowest verification that proves the changed behavior. Exercise a real runtime path when unit checks cannot establish the user-visible, integration, or operational result. Report commands, observed results, and known gaps accurately.

Before opening a PR, include only verification that gives a reviewer confidence beyond routine CI. Use an independent review for high-risk, cross-domain, or behaviorally hard-to-exercise changes. The deterministic `verify-gate` hook checks that a work-repository PR includes reviewer-useful evidence.
