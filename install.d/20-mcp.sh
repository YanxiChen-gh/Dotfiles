# shellcheck shell=sh
# Sourced by ../install.sh — function definitions only.

# Setup LangSmith MCP server configuration
# Usage: setup_langsmith_mcp
setup_langsmith_mcp() {
    echo "Setting up LangSmith MCP server..."

    # Check if Claude Code is available
    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping Claude LangSmith MCP CLI setup."
        echo "   Install Claude Code first, then run: claude mcp add ..."
        merge_cursor_mcp_langsmith
        return 1
    fi

    # Check if LangSmith MCP server is already configured
    if claude mcp list 2>/dev/null | grep -q "LangSmith"; then
        echo "✅ LangSmith MCP server already configured (Claude)"
        merge_cursor_mcp_langsmith
        return 0
    fi

    # Read API key from environment variable
    api_key="${LANGSMITH_API_KEY:-your_langsmith_api_key}"

    # Warn if using placeholder value
    if [ "$api_key" = "your_langsmith_api_key" ]; then
        echo "⚠️  No LANGSMITH_API_KEY found in environment"
        echo "   Using placeholder value. You'll need to update it later."
    fi

    # Add LangSmith MCP server using CLI
    echo "Adding LangSmith MCP server..."
    if claude mcp add --transport stdio --scope user "LangSmith" \
        --env LANGSMITH_API_KEY="$api_key" \
        -- uvx langsmith-mcp-server; then
        echo "✅ LangSmith MCP server added successfully"
        if [ "$api_key" = "your_langsmith_api_key" ]; then
            echo "📝 Remember to update the environment variable:"
            echo "   Run: claude mcp get 'LangSmith API MCP Server' to see configuration"
            echo "   You'll need to update LANGSMITH_API_KEY"
        fi
    else
        echo "⚠️  Warning: Failed to add LangSmith MCP server"
        echo "   You can try manually: claude mcp add --transport stdio 'LangSmith API MCP Server' \\"
        echo "     --env LANGSMITH_API_KEY=your_key -- uvx langsmith-mcp-server"
    fi

    merge_cursor_mcp_langsmith
}

# Setup Glean MCP server configuration
# Note: Glean MCP requires authentication. You'll need to authenticate after installation.
# Usage: setup_glean_mcp
setup_glean_mcp() {
    echo "Setting up Glean MCP server..."

    # Check if Claude Code is available
    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping Glean MCP setup."
        echo "   Install Claude Code first, then run: claude mcp add ..."
        return 1
    fi

    # Check if Glean MCP server is already configured
    if claude mcp list 2>/dev/null | grep -q "glean_default"; then
        echo "✅ Glean MCP server already configured"
        return 0
    fi

    # Add Glean MCP server using CLI
    echo "Adding Glean MCP server..."
    if claude mcp add glean_default https://vanta-be.glean.com/mcp/default \
        --transport http \
        --scope user; then
        echo "✅ Glean MCP server added successfully"
        echo "📝 Note: Glean MCP requires authentication. You'll need to authenticate to use it."
        echo "   See: https://docs.glean.com/user-guide/mcp/usage"
    else
        echo "⚠️  Warning: Failed to add Glean MCP server"
        echo "   You can try manually: claude mcp add glean_default https://vanta-be.glean.com/mcp/default \\"
        echo "     --transport http --scope user"
        echo "   See: https://docs.glean.com/user-guide/mcp/usage"
    fi
}

# Merge mcpServers from a fragment JSON into ~/.cursor/mcp.json (adds only missing server names).
# Fragment must be {"mcpServers": {...}} or a flat object of server name -> config.
# Usage: merge_cursor_mcp_fragment <path_to_json>
merge_cursor_mcp_fragment() {
    fragment_path=$1
    if ! command -v python3 >/dev/null 2>&1; then
        echo "⚠️  Python3 not found; skipping Cursor MCP merge ($fragment_path)"
        return 1
    fi
    if [ ! -f "$fragment_path" ]; then
        echo "⚠️  Cursor MCP fragment not found: $fragment_path"
        return 1
    fi
    python3 -c "
import json, os, sys
fragment_path = sys.argv[1]
cursor_dir = os.path.expanduser('~/.cursor')
os.makedirs(cursor_dir, exist_ok=True)
path = os.path.join(cursor_dir, 'mcp.json')
with open(fragment_path) as f:
    frag = json.load(f)
servers = frag['mcpServers'] if isinstance(frag, dict) and 'mcpServers' in frag else frag
if not isinstance(servers, dict):
    sys.exit('Invalid fragment: expected object or mcpServers object')
data = {}
if os.path.isfile(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        data = json.load(f)
ms = data.setdefault('mcpServers', {})
added = [k for k in servers if k not in ms]
for k, v in servers.items():
    if k not in ms:
        ms[k] = v
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
if added:
    print('✅ Cursor MCP: added', ', '.join(added))
else:
    print('✅ Cursor MCP: already had', ', '.join(servers.keys()))
" "$fragment_path" || return 1
}

# Merge LangSmith MCP entry for Cursor (from repo fragment).
merge_cursor_mcp_langsmith() {
    script_dir=$(resolve_script_dir) || return 1
    f="$script_dir/cursor/mcp-servers-personal.json"
    if [ ! -f "$f" ]; then
        return 0
    fi
    echo "Merging LangSmith into Cursor MCP config..."
    merge_cursor_mcp_fragment "$f" || true
}

# Add Datadog MCP to ~/.cursor/mcp.json using env placeholders (same vars as Claude setup).
merge_cursor_mcp_datadog() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi
    python3 <<'PY'
import json, os
path = os.path.expanduser("~/.cursor/mcp.json")
datadog = {
    "command": "npx",
    "args": [
        "datadog-mcp-server",
        "--apiKey", "${DATADOG_LOCAL_DEVELOPMENT_KEY_2}",
        "--appKey", "${DATADOG_APP_KEY}",
        "--site", "datadoghq.com",
        "--logsSite", "logs.datadoghq.com",
        "--metricsSite", "datadoghq.com",
    ],
}
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.isfile(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        data = json.load(f)
ms = data.setdefault("mcpServers", {})
if "datadog" not in ms:
    ms["datadog"] = datadog
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print("✅ Cursor MCP: added datadog")
else:
    print("✅ Cursor MCP: datadog already present")
PY
}

# Merge user MCP servers from Claude Code (~/.claude.json top-level mcpServers) into ~/.cursor/mcp.json.
# Strips Claude-only fields (e.g. type). Only adds/updates entries present in Claude; does not remove Cursor-only servers.
# Usage: sync_cursor_mcp_from_claude
sync_cursor_mcp_from_claude() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "⚠️  Python3 not found; skipping Claude → Cursor MCP sync"
        return 1
    fi
    claude_json="${HOME}/.claude.json"
    if [ ! -f "$claude_json" ]; then
        return 0
    fi
    script_dir=$(resolve_script_dir) || return 1
    python3 "$script_dir/scripts/sync_cursor_mcp_from_claude.py" || return $?
}

# Setup Datadog MCP server configuration (user scope — always available)
# Reads API keys from environment variables (DATADOG_LOCAL_DEVELOPMENT_KEY_2, DATADOG_APP_KEY)
setup_datadog_mcp() {
    echo "Setting up Datadog MCP server..."

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping Datadog MCP setup."
        return 1
    fi

    if claude mcp list 2>/dev/null | grep -q "datadog"; then
        echo "✅ Datadog MCP server already configured"
        return 0
    fi

    api_key="${DATADOG_LOCAL_DEVELOPMENT_KEY_2:-}"
    app_key="${DATADOG_APP_KEY:-}"

    if [ -z "$api_key" ] || [ -z "$app_key" ]; then
        echo "⚠️  DATADOG_LOCAL_DEVELOPMENT_KEY_2 or DATADOG_APP_KEY not set"
        echo "   Skipping Datadog MCP setup. Set these env vars and re-run."
        return 1
    fi

    echo "Adding Datadog MCP server..."
    if claude mcp add --transport stdio --scope user "datadog" \
        -- npx datadog-mcp-server \
        --apiKey "$api_key" \
        --appKey "$app_key" \
        --site datadoghq.com \
        --logsSite logs.datadoghq.com \
        --metricsSite datadoghq.com; then
        echo "✅ Datadog MCP server added successfully"
    else
        echo "⚠️  Warning: Failed to add Datadog MCP server"
    fi
}

# Setup Netlify MCP server (user scope — work only)
setup_netlify_mcp() {
    echo "Setting up Netlify MCP server..."

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping Netlify MCP setup."
        return 1
    fi

    if claude mcp list 2>/dev/null | grep -q "netlify"; then
        echo "✅ Netlify MCP server already configured"
        return 0
    fi

    echo "Adding Netlify MCP server..."
    if claude mcp add --scope user "netlify" \
        -- npx -y @netlify/mcp; then
        echo "✅ Netlify MCP server added successfully"
    else
        echo "⚠️  Warning: Failed to add Netlify MCP server"
        echo "   Try manually: claude mcp add netlify npx -- -y @netlify/mcp"
    fi
}

# Setup MongoDB MCP server (user scope — always available, connect at runtime via /connect-mongo)
setup_mongodb_mcp() {
    echo "Setting up MongoDB MCP server..."

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Warning: 'claude' command not found. Skipping MongoDB MCP setup."
        return 1
    fi

    if claude mcp list 2>/dev/null | grep -q "mongodb"; then
        echo "✅ MongoDB MCP server already configured"
        return 0
    fi

    echo "Adding MongoDB MCP server..."
    if claude mcp add --transport stdio --scope user "mongodb" \
        -- npx -y mongodb-mcp-server; then
        echo "✅ MongoDB MCP server added (use /connect-mongo to connect)"
    else
        echo "⚠️  Warning: Failed to add MongoDB MCP server"
    fi
}

# Merge work MCP servers into ~/.cursor/mcp.json (Glean, MongoDB, Netlify; Datadog if env vars set).
merge_cursor_work_mcp_entries() {
    script_dir=$(resolve_script_dir) || return 1
    work_fragment="$script_dir/cursor/mcp-servers-work.json"
    if [ -f "$work_fragment" ]; then
        echo "Merging work MCP servers into Cursor config..."
        merge_cursor_mcp_fragment "$work_fragment" || true
    fi
    api_key="${DATADOG_LOCAL_DEVELOPMENT_KEY_2:-}"
    app_key="${DATADOG_APP_KEY:-}"
    if [ -n "$api_key" ] && [ -n "$app_key" ]; then
        merge_cursor_mcp_datadog || true
    fi
}

