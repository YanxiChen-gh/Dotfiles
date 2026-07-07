# MCP Server Preferences

- **Glean MCP**: Use `glean_default` (search, chat, read_document) for all company/internal documentation lookups - Guru cards, Google Docs, Confluence, Slack threads, internal wikis, etc. Glean indexes all internal knowledge sources and respects permissions.
- **Google Drive MCP**: Do NOT use the `google-drive-mcp` tools. Use Glean instead for reading Google Docs and other company documents.
- **Datadog MCP**: Always available for logs, monitors, dashboards, and incident investigation.
- **MongoDB MCP**: If not connected, connect it before querying (in Claude Code, run `/connect-mongo`). Troubleshooting: https://app.getguru.com/card/T6jjXGKc/Connect-to-MongoDB-using-MongoDB-Compass
