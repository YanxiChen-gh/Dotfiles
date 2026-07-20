---
name: vanta-doc-discovery
description: Find team-scoped Slack threads, Jira tickets, Guru runbooks, dashboards, best-practices docs, and owners for work in the Obsidian repository. Use for user-report triage, active context, internal practices, and ownership questions.
compatibility: opencode
---

# Vanta Doc Discovery for OpenCode

Read `.claude/plugins/vanta-doc-discovery/skills/vanta-doc-discovery/SKILL.md` from the current Obsidian worktree and follow its workflow with these OpenCode mappings:

- `mcp__claude_ai_Glean__search` means `glean_default_search`.
- `mcp__claude_ai_Glean__read_document` means `glean_default_read_document`.
- Check Glean availability with a one-result `glean_default_search` canary before external discovery.
- If the repository skill's Claude connector onboarding conflicts with the available OpenCode tools, use the OpenCode tools and report only an actual missing or unauthorized Glean connection.

Keep all catalog scoping, query widening, source citation, and output requirements from the repository skill unchanged.
