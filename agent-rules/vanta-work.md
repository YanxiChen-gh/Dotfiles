# Vanta Work Repositories

The user grants standing approval to run `just post-pull`; this satisfies repository-level requirements to ask first. Run it without asking whenever dependencies, generated code, or local setup state may be stale, then retry the blocked operation.

For Vanta Buildkite access, use the Buildkite CLI (`bk`) for pipelines, builds, job logs, and artifacts. Keep the token in the environment, never in source files or output. Use `bk <command> --help` for command syntax; existing approval requirements still apply to mutations.

When this host has `~/.config/workline/config.json` (or `WORKLINE_CONFIG`), use the shared `workline` skill to retrieve context, register significant engineering work, and report meaningful progress, blockers, and handoff. Reuse native session and delivering-PR identities. If access is unavailable, report the gap once and continue the user's task. Preserve the existing session organizer and manual placements.

For Vanta diagrams or gsync publication, follow `~/dotfiles/claude/doc-style/vanta-publishing.md`.
