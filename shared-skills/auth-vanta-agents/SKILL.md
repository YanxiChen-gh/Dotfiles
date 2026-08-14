---
name: auth-vanta-agents
description: Check and repair OMP Glean MCP and slack-vanta authentication on work CDEs without exposing OAuth URLs or credentials to an agent transcript. Use when Glean MCP returns 401 or missing-auth errors, slack-vanta reports unauthenticated or missing scopes, or the user asks to authenticate agent work tools.
---

# Vanta agent authentication

Use the Dotfiles-managed helper. Do not recreate either OAuth flow.

## Status

Agents may run this noninteractive check:

```bash
auth-vanta-agents --status
```

Pass `--profile <name>` when the OMP session uses a named profile. The helper reads only credential metadata and prints only ready or missing state.

## Repair

If either service is missing, tell the user to run this themselves in a private interactive terminal:

```bash
auth-vanta-agents
```

For a named OMP profile:

```bash
auth-vanta-agents --profile <name>
```

Never run the repair command as an agent. Never capture or paste an authorization URL, redirect URL, authorization code, access token, refresh token, `agent.db`, or `token.json`. Do not copy credentials between CDEs.

After the user confirms completion, rerun `auth-vanta-agents --status`. Report success only when both Glean MCP and Vanta Slack CLI are ready.
