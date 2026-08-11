---
name: ona-oauth-callback
description: Bridges loopback-only OAuth localhost callbacks through Ona port forwarding. Use for OAuth CLI login in an Ona CDE, localhost refused to connect, or when an Ona-forwarded callback cannot reach 127.0.0.1.
---

# Ona OAuth Callback

Use `bridge.sh` to expose a loopback-only OAuth callback without handling its URL, authorization code, token, or credentials. The original OAuth CLI displays the authorization URL.

Direct Ona forwarding cannot reach a callback bound only to `127.0.0.1`: Ona accepts traffic on an all-interface environment port, while the OAuth CLI intentionally accepts traffic only on loopback. The helper owns a temporary `socat` bridge between those ports. Registration always uses `creator_only`.

## Workflow

1. Ask the user to start the original OAuth CLI in their private CDE terminal. Agents must not run an authentication command whose output enters a transcript. The user keeps it running and shares only its localhost callback port, never the authorization URL, redirect, code, token, or credentials.
2. Resolve the explicit Ona environment ID with `ona environment get --context environment --field id`.
3. Select an unused remote port distinct from the callback port.
4. Ona port registration is an external write. Ask for approval unless the user already requested this forwarding workflow.
5. Run:

   ```bash
   ~/.agents/skills/ona-oauth-callback/bridge.sh start \
     --callback-port <callback> \
     --remote-port <remote> \
     --environment-id <environment-id>
   ```

6. Give the user only the exact Mac foreground command printed by the helper. They should keep it running while opening the authorization URL shown in their private terminal.
7. Wait for the original OAuth CLI to complete. Tell the user to press `Ctrl-C` in the Mac forwarding command afterward.
8. Stop the owned resources with the exact cleanup command printed by `start`.
9. Verify cleanup. `status --remote-port <remote>` should report absent ownership state after a successful stop.

Use the helper for every managed `start`, `status`, and `stop` operation. It serializes lifecycle changes for each remote port and refuses to close a registration or tmux session whose ownership no longer matches.

## Diagnostics

- `localhost refused to connect`: keep the original OAuth CLI running and confirm its callback listens on exactly `127.0.0.1:<callback>`.
- Existing listener, registration, or ownership state: choose another remote port or clean up the matching owned bridge. Never adopt an existing resource.
- Missing `ona`, `tmux`, `socat`, `ss`, `flock`, or Python 3: install or restore that prerequisite outside this helper.
- Inspect owned state with `bridge.sh status --remote-port <remote>`.

The state file contains only port numbers, environment ID, managed session name, registration name, and a random ownership ID. It is mode `0600` and contains no OAuth data.
