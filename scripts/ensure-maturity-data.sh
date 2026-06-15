#!/usr/bin/env bash
# Lazily provision the PRIVATE maturity-data repo into the dotfiles agent-maturity dir.
# Idempotent and a fast no-op once set up. Called by the maturity skills at invocation time
# — NOT from install.sh — because gh is reliably authenticated during a session but often
# not at env-provisioning time, and the data is only needed when a skill actually runs.
#
# Clones YanxiChen-gh/agent-maturity-data (private) and symlinks interventions.jsonl + tracker.md
# into ~/dotfiles/claude/agent-maturity/ so scripts/skills referencing those fixed paths resolve
# into the private clone. Never clobbers a pre-existing real file (warns instead).
set -uo pipefail

REPO="${AGENT_MATURITY_DATA_REPO:-YanxiChen-gh/agent-maturity-data}"
DATA="${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}"
DOTDIR="${AGENT_MATURITY_DIR:-$HOME/dotfiles/claude/agent-maturity}"

if [ ! -d "$DATA/.git" ]; then
  command -v gh >/dev/null || { echo "ensure-maturity-data: gh not on PATH; cannot clone private data repo" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ensure-maturity-data: gh not authenticated (run 'gh auth login') — private data repo needs it" >&2; exit 1; }
  echo "Provisioning private maturity data: cloning $REPO → $DATA"
  gh repo clone "$REPO" "$DATA" >/dev/null 2>&1 || { echo "ensure-maturity-data: clone failed (no access to $REPO?)" >&2; exit 1; }
fi

mkdir -p "$DOTDIR"
for f in interventions.jsonl tracker.md; do
  link="$DOTDIR/$f"; target="$DATA/$f"
  [ -e "$target" ] || : > "$target"            # first run: empty file so the symlink isn't dangling
  if [ -L "$link" ] || [ ! -e "$link" ]; then
    ln -sfn "$target" "$link"
  elif [ ! "$link" -ef "$target" ]; then
    echo "ensure-maturity-data: $link is a real file, not the symlink — leaving it; reconcile manually." >&2
  fi
done
echo "maturity data ready ($DATA)"
