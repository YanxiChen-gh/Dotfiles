---
name: auth-vanta-agents
description: Use when OMP Glean MCP returns 401 or missing-auth errors, slack-vanta reports unauthenticated or missing scopes, or the user asks to authenticate agent work tools on a work CDE.
---

# Vanta agent authentication

Use OMP's native reauthentication command for Glean. Use the Dotfiles-managed helper for status and Slack authentication. Do not recreate either OAuth flow.

## Status

Agents may run this noninteractive check:

```bash
auth-vanta-agents --status
```

Pass `--profile <name>` when the OMP session uses a named profile. The helper reads only credential metadata and prints only ready or missing state.

## Repair

If Glean MCP is missing in an active OMP session, tell the user to type this directly into the current OMP input:

```text
/mcp reauth glean_default
```

Do not launch another OMP session or send the user to another terminal for Glean authentication. OMP handles the slash command locally.

If the Vanta Slack CLI is missing, tell the user to run `auth-vanta-agents` themselves in a private interactive terminal. Once Glean is ready, the helper skips Glean and opens only the Slack OAuth flow.

Never run a repair command as an agent. Never capture or paste an authorization URL, redirect URL, authorization code, access token, refresh token, `agent.db`, or `token.json`. Do not copy credentials between CDEs.

After the user confirms completion, rerun `auth-vanta-agents --status`. Pass `--profile <name>` for a named OMP profile. Report success only when both Glean MCP and Vanta Slack CLI are ready.
