---
name: vanta-doc-discovery
description: Find team-scoped Slack threads, Jira tickets, Guru runbooks, dashboards, best-practices docs, and owners for work in the Obsidian repository. Use for user-report triage, active context, internal practices, and ownership questions.
---

# Vanta Doc Discovery

Read `.claude/plugins/vanta-doc-discovery/skills/vanta-doc-discovery/SKILL.md` from the current Obsidian worktree and follow its workflow.

## Runtime tool selection

Use the active runtime's mounted Glean search and document-read tools. Mounted tool capabilities take precedence over client-specific tool names or connector onboarding instructions in the repository skill. Determine availability from the tools mounted in the current runtime. Do not use another client's CLI, including `opencode mcp list`, to infer whether Glean is available.

Keep all catalog scoping, query widening, source citation, and output requirements from the repository skill unchanged.

## OpenCode only

Only when the active client is OpenCode, apply these mappings:

- `mcp__claude_ai_Glean__search` means `glean_default_search`.
- `mcp__claude_ai_Glean__read_document` means `glean_default_read_document`.
- Check Glean availability with a one-result `glean_default_search` canary before external discovery.
- If the repository skill's Claude connector onboarding conflicts with the mounted OpenCode tools, use the mounted OpenCode tools and report only an actual missing or unauthorized Glean connection.

## OMP and other runtimes

In OMP and every other non-OpenCode client, use its mounted tools directly without translating them to the OpenCode names above.
