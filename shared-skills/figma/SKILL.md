---
name: figma
description: Use when configuring or authenticating Figma MCP in an Ona CDE, or when reading Figma designs through figma-mcp-cli.
---

# Figma MCP

Use the Dotfiles-managed `figma-mcp-cli` for Figma's remote MCP server. OMP is not a supported direct Figma MCP client.

## Setup

Run the non-authenticating installer when the wrapper is missing:

```bash
~/dotfiles/mcp2cli/figma/setup-figma
```

The installer pins `mcp==1.22.0`, copies non-secret client metadata to `~/.config/mcp2cli-figma`, and leaves OAuth state in mcp2cli's private user cache.

## Authentication in Ona

Agents never run a command that may print an OAuth URL. Ask the user to run this in a private CDE terminal:

```bash
figma-mcp-cli --list
```

The user keeps it running and never shares its URL, redirect, code, or token. If the loopback callback is refused, they share only the callback port.

**REQUIRED SUB-SKILL:** Use `ona-oauth-callback` to bridge that port. Never inspect or copy the OAuth cache.

After the user confirms completion, verify access:

```bash
figma-mcp-cli --pretty whoami
```

Report the account and seat type without printing other credential state.

## Reading designs

Extract `fileKey` from `/design/<fileKey>/...` and convert `node-id=1-2` to `1:2`.

```bash
figma-mcp-cli get-metadata \
  --file-key <fileKey> \
  --node-id <nodeId> \
  --client-languages typescript \
  --client-frameworks react
```

Use `get-screenshot` for visual fidelity and `get-variable-defs` for design tokens. Use `get-design-context` only for targeted implementation context, with `--disable-code-connect --exclude-screenshot` unless the user requests otherwise.
