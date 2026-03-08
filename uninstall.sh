#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
AGENTS_DIR="$CLAUDE_DIR/agents"

echo "AutoCode — Removing skill files"
echo ""

# Remove command symlinks
echo "Removing commands..."
for file in "$SCRIPT_DIR/commands/"*.md; do
    filename=$(basename "$file")
    target="$COMMANDS_DIR/$filename"
    if [ -L "$target" ]; then
        echo "  Removing: $filename"
        rm -f "$target"
    fi
done

# Remove agent symlinks
echo "Removing agents..."
for file in "$SCRIPT_DIR/agents/"*.md; do
    filename=$(basename "$file")
    target="$AGENTS_DIR/$filename"
    if [ -L "$target" ]; then
        echo "  Removing: $filename"
        rm -f "$target"
    fi
done

echo ""
echo "Done. AutoCode has been uninstalled."
