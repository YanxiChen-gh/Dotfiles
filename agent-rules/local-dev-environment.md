# Local Dev Environment (Worktrees & Port Forwarding)

## Git worktrees

After creating a git worktree (any repo), provision it with `~/dotfiles/scripts/provision-worktree.sh <path>` - it hardlink-seeds `node_modules` and copies git-ignored local config (`.claude/settings.local.json`, `.dd-agent.env`, `.env*`); idempotent, no-op for anything absent. Don't run `yarn install` / `turbo generate-types` in a worktree unless you'll actually build there.

In Zed remote sessions, agent-created worktrees don't appear in the sidebar's "Open Worktrees" list, but they do show in the `git: worktree` picker (`cmd-shift-P`) - so `git worktree add` is fine; open it from there.

## Exposing local dev servers (port forwarding)

To reach a local server on a remote CDE from a laptop, prefer in order:

1. **`~/dotfiles/scripts/expose-port-tailscale.sh <local-port> [verify-path]`** (preferred) - handles the whole Ona/tailnet chain and verifies through the tailnet path. It encodes two hard-won constraints; don't work around them by hand: serve on **tailnet port 8080 only** (ACLs for `tag:ona-dev` admit only that port - others hang from a laptop while self-tests still pass), and **verify through the tailnet path, not a localhost curl**.
2. **Editor port-forward** - VS Code/Cursor Ports panel (needs a human click).
3. **ngrok** - last resort (public URL; tear it down when done).

Don't use a static share/publish/export when you need a *live* server - it drops the interactive connection back to the agent.
