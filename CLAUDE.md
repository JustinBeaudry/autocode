# AutoCode

Open-source autonomous code factory for Claude Code. Pure skill files — no build step, no dependencies.

## Project Structure

- `commands/` — Claude Code slash commands (user-invokable skills)
- `agents/` — Agent role definitions (spawned by the orchestrator, not user-invokable)
- `schemas/` — JSON schema for `autocode.manifest.json`
- `examples/` — Example manifests for different project types
- `docs/` — Documentation

## Key Concepts

- **Manifest**: `autocode.manifest.json` is generated per-repo by `/autocode-bootstrap`. It's the immutable contract agents run against.
- **Agents are constrained**: Scout reads only, Architect writes specs only, Builder writes source only, Tester writes tests only, Reviewer writes nothing.
- **Memory**: Per-repo memory in `.autocode/memory/` prevents retry loops and accumulates lessons.
- **Progressive difficulty**: Levels 1-6, auto-advances after 3 consecutive successes.

## Development

When editing skill files:
- Commands in `commands/` are user-invokable via `/command-name`
- Agents in `agents/` are spawned by the orchestrator — they're NOT slash commands
- All files are markdown — no code to build or test
- Test changes by running `./install.sh` and using the commands in Claude Code
