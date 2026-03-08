#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
AGENTS_DIR="$CLAUDE_DIR/agents"

echo "AutoCode — Installing skill files"
echo ""

# Create directories if they don't exist
mkdir -p "$COMMANDS_DIR"
mkdir -p "$AGENTS_DIR"

# Symlink command files
echo "Linking commands..."
for file in "$SCRIPT_DIR/commands/"*.md; do
    filename=$(basename "$file")
    target="$COMMANDS_DIR/$filename"
    if [ -L "$target" ] || [ -f "$target" ]; then
        echo "  Updating: $filename"
        rm -f "$target"
    else
        echo "  Adding:   $filename"
    fi
    ln -s "$file" "$target"
done

# Symlink agent files
echo "Linking agents..."
for file in "$SCRIPT_DIR/agents/"*.md; do
    filename=$(basename "$file")
    target="$AGENTS_DIR/$filename"
    if [ -L "$target" ] || [ -f "$target" ]; then
        echo "  Updating: $filename"
        rm -f "$target"
    else
        echo "  Adding:   $filename"
    fi
    ln -s "$file" "$target"
done

echo ""
echo "Done. AutoCode commands are now available in Claude Code:"
echo "  /autocode-bootstrap  — Analyze repo and generate manifest"
echo "  /autocode            — Run the autonomous code factory"
echo "  /autocode-status     — View factory status and metrics"
echo "  /autocode-stop       — Gracefully stop the factory"
