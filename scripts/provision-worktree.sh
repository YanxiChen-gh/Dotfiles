#!/usr/bin/env bash
# provision-worktree.sh - make a freshly-created git worktree usable without a cold install.
#
# Hardlinks node_modules from the repo's main worktree (instant, ~0 extra disk) and copies
# git-ignored local config that a linked worktree doesn't inherit. Repo-agnostic, idempotent,
# and a no-op for anything that's absent - safe to run after any `git worktree add`.
#
# Usage: provision-worktree.sh <worktree-path>
set -euo pipefail

WT="${1:?usage: provision-worktree.sh <worktree-path>}"
WT="$(cd "$WT" && pwd -P)"

# Main worktree = the first entry of `git worktree list` (the primary checkout).
MAIN="$(git -C "$WT" worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
if [[ -z "${MAIN:-}" || "$MAIN" == "$WT" ]]; then
  echo "provision-worktree: no separate main worktree resolved for $WT - nothing to do." >&2
  exit 0
fi

# 1. Seed node_modules via hardlinks. Exclude Turbo's .cache so builds in this worktree
#    don't write through the shared inodes into the main checkout's cache.
if [[ -d "$MAIN/node_modules" && ! -d "$WT/node_modules" ]]; then
  echo "provision-worktree: hardlink-seeding node_modules from $MAIN ..."
  rsync -a --link-dest="$MAIN/node_modules" --exclude='.cache' \
    "$MAIN/node_modules/" "$WT/node_modules/"
fi

# 2. Copy git-ignored local config that doesn't carry into a linked worktree.
for rel in .claude/settings.local.json .dd-agent.env .env .env.local; do
  if [[ -f "$MAIN/$rel" && ! -e "$WT/$rel" ]]; then
    mkdir -p "$WT/$(dirname "$rel")"
    cp "$MAIN/$rel" "$WT/$rel" && echo "provision-worktree: copied $rel"
  fi
done

echo "provision-worktree: done."
echo "  (Run 'yarn install && turbo generate-types' in the worktree only if you'll build there -"
echo "   reading and searching need neither.)"
