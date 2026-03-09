#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
AGENTS_DIR="$CLAUDE_DIR/agents"

# Verify we're running from a directory that has commands/ and agents/
if [ ! -d "$SCRIPT_DIR/commands" ] || [ ! -d "$SCRIPT_DIR/agents" ]; then
    echo "Error: Run this script from the autocode directory."
    echo "Expected to find commands/ and agents/ in: $SCRIPT_DIR"
    exit 1
fi

FORCE=0
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    FORCE=1
fi

echo "AutoCode — Installing skill files"
echo ""

# Create directories if they don't exist
mkdir -p "$COMMANDS_DIR"
mkdir -p "$AGENTS_DIR"

commands_installed=0
commands_skipped=0
agents_installed=0
agents_skipped=0
had_errors=0

# install_links SOURCE_DIR TARGET_DIR TYPE
# TYPE is "command" or "agent" (used for display only)
install_links() {
    local source_dir="$1"
    local target_dir="$2"
    local type_label="$3"
    local installed=0
    local skipped=0

    for file in "$source_dir/"*.md; do
        [ -f "$file" ] || continue
        local filename
        filename=$(basename "$file")
        local target="$target_dir/$filename"

        # Check if symlink already exists
        if [ -L "$target" ]; then
            local current_target
            current_target=$(readlink "$target")
            if [ "$current_target" = "$file" ]; then
                echo "  [skip] $filename (already installed)"
                skipped=$((skipped + 1))
                continue
            else
                # Symlink exists but points elsewhere
                if [ "$FORCE" = "1" ]; then
                    echo "  [overwrite] $filename (was linked to $current_target)"
                    rm -f "$target"
                else
                    echo "  [warn] $filename already exists and points to: $current_target"
                    echo "         Use --force to overwrite."
                    had_errors=1
                    continue
                fi
            fi
        elif [ -f "$target" ]; then
            # Regular file (not a symlink) exists at the target
            if [ "$FORCE" = "1" ]; then
                echo "  [overwrite] $filename (replacing regular file)"
                rm -f "$target"
            else
                echo "  [warn] $filename exists as a regular file (not a symlink)."
                echo "         Use --force to overwrite."
                had_errors=1
                continue
            fi
        fi

        # Create symlink
        ln -s "$file" "$target"

        # Verify the symlink was created and resolves correctly
        if [ -L "$target" ] && [ -f "$target" ]; then
            echo "  [ok] $filename"
            installed=$((installed + 1))
        else
            echo "  [error] $filename — symlink created but does not resolve"
            had_errors=1
        fi
    done

    # Return counts via global variables (bash workaround for subshell issue)
    eval "${type_label}_installed=$installed"
    eval "${type_label}_skipped=$skipped"
}

echo "Linking commands..."
install_links "$SCRIPT_DIR/commands" "$COMMANDS_DIR" "commands"

echo ""
echo "Linking agents..."
install_links "$SCRIPT_DIR/agents" "$AGENTS_DIR" "agents"

echo ""

# Summary
total_installed=$((commands_installed + agents_installed))
total_skipped=$((commands_skipped + agents_skipped))

if [ "$total_installed" -eq 0 ] && [ "$total_skipped" -gt 0 ] && [ "$had_errors" -eq 0 ]; then
    echo "AutoCode is already installed. Nothing to do."
elif [ "$total_installed" -gt 0 ]; then
    echo "Installed $commands_installed command(s) and $agents_installed agent(s) to ~/.claude/"
    if [ "$total_skipped" -gt 0 ]; then
        echo "Skipped $commands_skipped command(s) and $agents_skipped agent(s) (already installed)."
    fi
fi

if [ "$had_errors" -ne 0 ]; then
    echo ""
    echo "Some files were skipped due to conflicts. Re-run with --force to overwrite."
    exit 1
fi
