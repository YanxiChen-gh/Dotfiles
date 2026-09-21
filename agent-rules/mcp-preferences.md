# MCP Server Preferences

- **Glean MCP**: `glean_default` is configured and available in OMP. For every company or internal-knowledge lookup, MUST use its `search`, `chat`, or `read_document` tools before external web search. This includes Guru, Google Docs, Confluence, Slack, and internal wikis. Glean indexes these sources and respects permissions.
- **Google Drive MCP**: Do NOT use the `google-drive-mcp` tools. Use Glean instead for reading Google Docs and other company documents.
- **Datadog MCP**: Always available for logs, monitors, dashboards, and incident investigation.
- **MongoDB MCP**: If not connected, connect it before querying (in Claude Code, run `/connect-mongo`). Troubleshooting: https://app.getguru.com/card/T6jjXGKc/Connect-to-MongoDB-using-MongoDB-Compass
