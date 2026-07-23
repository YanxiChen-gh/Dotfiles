# Local Dev Environment (Worktrees & Port Forwarding)

## Git worktrees

After creating a git worktree (any repo), provision it with `~/dotfiles/scripts/provision-worktree.sh <path>` - it hardlink-seeds `node_modules` and copies git-ignored local config (`.claude/settings.local.json`, `.dd-agent.env`, `.env*`); idempotent, no-op for anything absent. Don't run `yarn install` / `turbo generate-types` in a worktree unless you'll actually build there.

In Zed remote sessions, agent-created worktrees don't appear in the sidebar's "Open Worktrees" list, but they do show in the `git: worktree` picker (`cmd-shift-P`) - so `git worktree add` is fine; open it from there.

## Resolving browser URLs

Always run `~/dotfiles/scripts/expose-port.sh <local-port> [verify-path]` before giving the user a local-server URL. The script owns environment detection, setup, and verification: Ona uses the Tailscale path, macOS returns localhost, and unknown remotes fail closed. Return the single URL it prints on stdout. Do not ask the user whether the agent is in a CDE or choose the exposure method yourself.

The dispatcher delegates Ona to `expose-port-tailscale.sh`, which currently manages one root exposure on tailnet port 8080 and verifies it through the tailnet path, not a localhost curl. Other ACL-permitted ports are reserved for Vanta development services, so don't borrow them for agent tools.

One CDE cannot expose both Vanta and Lavish through this helper at the same time. If it reports that port 8080 already exposes a live target, do not infer that an HTTP 502 makes the mapping stale and do not replace it silently. Explain the conflict and ask the user which exposure to keep:

- **Keep Vanta:** leave its Tailscale exposure and local services untouched. End the current Lavish review or use the fallback below only after the user chooses this option.
- **Keep Lavish:** after the user chooses this option, replace only the Tailscale Serve exposure and retry `expose-port.sh`. Leave Vanta running locally; do not run `just dev-stop-all` or stop its containers.

This choice affects every agent in the CDE because Lavish shares one local server and Tailscale Serve state is host-wide. Never stop another Lavish session, remove an existing Serve mapping, or make either URL unavailable without the explicit choice above.

If the dispatcher rejects an unsupported remote environment, fall back in order:

1. **Editor port-forward** - VS Code/Cursor Ports panel (needs a human click).
2. **ngrok** - last resort (public URL; tear it down when done).

Don't use a static share/publish/export when you need a *live* server - it drops the interactive connection back to the agent.
