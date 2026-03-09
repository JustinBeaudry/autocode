#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
AGENTS_DIR="$CLAUDE_DIR/agents"

echo "AutoCode — Removing skill files"
echo ""

commands_removed=0
agents_removed=0
found_any=0

# remove_links SOURCE_DIR TARGET_DIR TYPE
remove_links() {
    local source_dir="$1"
    local target_dir="$2"
    local type_label="$3"
    local removed=0

    # If target directory doesn't exist, nothing to remove
    if [ ! -d "$target_dir" ]; then
        eval "${type_label}_removed=0"
        return
    fi

    for file in "$source_dir/"*.md; do
        [ -f "$file" ] || continue
        local filename
        filename=$(basename "$file")
        local target="$target_dir/$filename"

        if [ -L "$target" ]; then
            local current_target
            current_target=$(readlink "$target")

            # Only remove if the symlink points back into this autocode directory
            case "$current_target" in
                "$SCRIPT_DIR/"*)
                    echo "  Removed: $filename"
                    rm -f "$target"
                    removed=$((removed + 1))
                    found_any=1
                    ;;
                *)
                    echo "  Skipped: $filename (points to $current_target, not managed by AutoCode)"
                    ;;
            esac
        fi
    done

    eval "${type_label}_removed=$removed"
}

echo "Checking commands..."
remove_links "$SCRIPT_DIR/commands" "$COMMANDS_DIR" "commands"

echo ""
echo "Checking agents..."
remove_links "$SCRIPT_DIR/agents" "$AGENTS_DIR" "agents"

echo ""

total_removed=$((commands_removed + agents_removed))

if [ "$total_removed" -eq 0 ] && [ "$found_any" -eq 0 ]; then
    echo "AutoCode is not installed. Nothing to remove."
else
    echo "Removed $commands_removed command(s) and $agents_removed agent(s) from ~/.claude/"
fi
