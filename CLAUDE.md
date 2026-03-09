# AutoCode

Your repo's engineering department. Features, bugs, coverage, refactoring — from a unified work queue. Pure skill files — no build step, no dependencies.

## Project Structure

- `commands/` — Claude Code slash commands (user-invokable skills)
- `agents/` — Agent role definitions (spawned by the orchestrator, not user-invokable)
- `schemas/` — JSON schema for `autocode.manifest.json`
- `examples/` — Example manifests for different project types
- `docs/` — Documentation

## Key Concepts

- **Manifest**: `autocode.manifest.json` is generated per-repo by `/autocode-bootstrap`. It's the immutable contract agents run against.
- **Work Queue**: Multiple sources feed into a unified, prioritized work queue: focus overrides, GitHub Issues, coverage gaps, backlog tasks, PR review feedback, and tech debt signals.
- **Work Types**: Each work item has a type (`coverage`, `feature`, `bugfix`, `refactor`, `docs`, `dependency`, `review_response`) that determines pipeline routing — which agents are spawned and skipped.
- **Agents are constrained**: Scout reads only, Architect writes specs only, Builder writes source only, Tester writes tests only, Reviewer writes nothing. All agents receive lessons from previous cycles.
- **Memory**: Per-repo memory in `.autocode/memory/` prevents retry loops and accumulates lessons.
- **Progressive difficulty**: Levels 1-6, auto-advances after 3 consecutive successes. Higher levels unlock more work types (L1-2: coverage only, L3+: bugs, L5+: features).

## Commands

| Command | Description |
|---------|-------------|
| `/autocode-bootstrap` | Analyze repo and generate manifest |
| `/autocode` | Run the autonomous code factory |
| `/autocode-status` | View current factory status and metrics |
| `/autocode-stop` | Gracefully stop the factory |
| `/autocode-report` | Generate a shareable summary |
| `/autocode-focus` | Manage the priority work queue |
| `/autocode-next` | Preview the next cycle (dry run) |

## Development

When editing skill files:
- Commands in `commands/` are user-invokable via `/command-name`
- Agents in `agents/` are spawned by the orchestrator — they're NOT slash commands
- All files are markdown — no code to build or test
- Test changes by running `./install.sh` and using the commands in Claude Code
