#!/bin/sh
#
# Cursor Sync Script
# Exports current Cursor configuration to Dotfiles for version control
#
# Usage:
#   ./cursor-sync.sh          # Export current config
#   ./cursor-sync.sh --commit # Export and commit changes
#

set -e

# Detect OS and set paths
case "$(uname -s)" in
    Darwin*)
        CURSOR_USER_DIR="$HOME/Library/Application Support/Cursor/User"
        ;;
    Linux*)
        CURSOR_USER_DIR="$HOME/.config/Cursor/User"
        ;;
    *)
        echo "❌ Unsupported OS"
        exit 1
        ;;
esac

CURSOR_HOME_DIR="$HOME/.cursor"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CURSOR_DOTFILES="$SCRIPT_DIR/cursor"

echo "Syncing Cursor configuration to Dotfiles..."

# Export settings.json (only if it's not already a symlink)
if [ -f "$CURSOR_USER_DIR/settings.json" ] && [ ! -L "$CURSOR_USER_DIR/settings.json" ]; then
    echo "Exporting settings.json..."
    cp "$CURSOR_USER_DIR/settings.json" "$CURSOR_DOTFILES/settings.json"
    echo "✅ settings.json exported"
elif [ -L "$CURSOR_USER_DIR/settings.json" ]; then
    echo "ℹ️  settings.json is already symlinked (changes auto-sync)"
fi

# Export keybindings.json (only if it's not already a symlink)
if [ -f "$CURSOR_USER_DIR/keybindings.json" ] && [ ! -L "$CURSOR_USER_DIR/keybindings.json" ]; then
    echo "Exporting keybindings.json..."
    cp "$CURSOR_USER_DIR/keybindings.json" "$CURSOR_DOTFILES/keybindings.json"
    echo "✅ keybindings.json exported"
elif [ -L "$CURSOR_USER_DIR/keybindings.json" ]; then
    echo "ℹ️  keybindings.json is already symlinked (changes auto-sync)"
fi

# Export snippets (only if not symlinked)
if [ -d "$CURSOR_USER_DIR/snippets" ] && [ ! -L "$CURSOR_USER_DIR/snippets" ]; then
    echo "Exporting snippets..."
    rm -rf "$CURSOR_DOTFILES/snippets"
    cp -r "$CURSOR_USER_DIR/snippets" "$CURSOR_DOTFILES/snippets"
    echo "✅ snippets exported"
elif [ -L "$CURSOR_USER_DIR/snippets" ]; then
    echo "ℹ️  snippets is already symlinked (changes auto-sync)"
fi

# Export extension list
if [ -f "$CURSOR_HOME_DIR/extensions/extensions.json" ]; then
    echo "Exporting extension list..."
    python3 -c "
import json
import sys

with open('$CURSOR_HOME_DIR/extensions/extensions.json', 'r') as f:
    exts = json.load(f)

ids = sorted(set(e['identifier']['id'] for e in exts))
print('\n'.join(ids))
" > "$CURSOR_DOTFILES/extensions.txt"
    count=$(wc -l < "$CURSOR_DOTFILES/extensions.txt" | tr -d ' ')
    echo "✅ extensions.txt exported ($count extensions)"
fi

# Export skills (only if not symlinked)
if [ -d "$CURSOR_HOME_DIR/skills-cursor" ] && [ ! -L "$CURSOR_HOME_DIR/skills-cursor" ]; then
    echo "Exporting agent skills..."
    rm -rf "$CURSOR_DOTFILES/skills"
    cp -r "$CURSOR_HOME_DIR/skills-cursor" "$CURSOR_DOTFILES/skills"
    echo "✅ agent skills exported"
elif [ -L "$CURSOR_HOME_DIR/skills-cursor" ]; then
    echo "ℹ️  skills is already symlinked (changes auto-sync)"
fi

echo ""
echo "✅ Sync complete!"

# Optional: commit changes
if [ "$1" = "--commit" ]; then
    echo ""
    echo "Committing changes..."
    cd "$SCRIPT_DIR"
    git add cursor/
    if git diff --cached --quiet; then
        echo "ℹ️  No changes to commit"
    else
        git commit -m "sync: update Cursor configuration"
        echo "✅ Changes committed"
        echo "   Run 'git push' to push to remote"
    fi
fi
