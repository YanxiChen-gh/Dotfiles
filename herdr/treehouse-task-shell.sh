#!/bin/sh
set -eu

# Treehouse invokes $SHELL with no arguments from the acquired checkout. Restore
# the user's shell for every process created after this ownership bridge.
SHELL="${DOTFILES_HERDR_ORIGINAL_SHELL:-/bin/sh}"
export SHELL

launcher="${DOTFILES_HERDR_LAUNCHER:-$HOME/dotfiles/herdr/new-agent-tab.sh}"
exec "$launcher" --treehouse-ready
