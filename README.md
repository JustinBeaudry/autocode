# AutoCode

**Autonomous code factory for Claude Code.**

A team of specialized AI agents run in a continuous loop — discovering work, implementing code, writing tests, reviewing PRs, and shipping merges — all unattended.

Inspired by [Karpathy's autoresearch](https://x.com/karpathy/status/1886192184808149383). Built for [Claude Code's auto-accept mode](https://docs.anthropic.com/en/docs/claude-code).

## Quick Start

```bash
# 1. Clone
git clone https://github.com/ajsai47/autocode.git
cd autocode

# 2. Install (symlinks skills into ~/.claude/)
./install.sh

# 3. Navigate to your project
cd ~/your-project

# 4. Bootstrap — analyzes your repo, generates a manifest
# (in Claude Code)
/autocode-bootstrap

# 5. Run the factory
/autocode
```

## How It Works

```
                    ┌─────────────────────────────────────┐
                    │         autocode.manifest.json       │
                    │  (repo config, commands, coverage,   │
                    │   guardrails, difficulty levels)      │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │          ORCHESTRATOR (/autocode)     │
                    │  Reads manifest, selects work,       │
                    │  spawns agents, manages cycle loop   │
                    └──────────────┬──────────────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
    ┌─────▼─────┐           ┌─────▼─────┐           ┌─────▼─────┐
    │   SCOUT   │           │ ARCHITECT │           │  BUILDER  │
    │ (read-only│──context─▶│ (spec     │───spec──▶│ (source   │
    │  explore) │           │  writer)  │           │  files)   │
    └───────────┘           └───────────┘           └─────┬─────┘
                                                          │
                                                    ┌─────▼─────┐
                                                    │  TESTER   │
                                                    │ (test     │
                                                    │  files)   │
                                                    └─────┬─────┘
                                                          │
                                                    ┌─────▼─────┐
                                                    │ REVIEWER  │
                                                    │ (approve/ │
                                                    │  reject)  │
                                                    └─────┬─────┘
                                                          │
                                              ┌───────────▼───────────┐
                                              │  PR created & merged  │
                                              └───────────────────────┘
```

## Architecture

### Manifest-Driven

The `autocode.manifest.json` is the contract. The bootstrap command (`/autocode-bootstrap`) analyzes your repo once and writes it down. Agents don't discover — they read the manifest.

### Constrained Agents

Each agent has strict boundaries:

| Agent | Can Read | Can Write | Model |
|-------|----------|-----------|-------|
| Scout | Everything | Nothing | Sonnet |
| Architect | Everything | Specs only | Sonnet |
| Builder | Everything | Source files only | Opus |
| Tester | Everything | Test files only | Sonnet |
| Reviewer | Everything | Nothing | Opus |

### Progressive Difficulty

Starts with easy wins, graduates to harder tasks:

1. Pure function coverage (no mocking)
2. Utility/helper coverage (light mocking)
3. Fix existing failing tests
4. Integration coverage (DB, API mocks)
5. Feature implementation from tickets
6. Refactoring with behavior preservation

### Memory System

Per-repo memory in `.autocode/memory/` prevents loops and accumulates knowledge:
- `fixes.md` — what was fixed and how
- `failures.md` — what didn't work (don't retry)
- `velocity.md` — PRs shipped, merge rates, timing
- `coverage.md` — per-file coverage progression
- `lessons.md` — patterns that work, patterns that fail

## Commands

| Command | Description |
|---------|-------------|
| `/autocode-bootstrap` | Analyze repo and generate manifest |
| `/autocode` | Run the autonomous code factory |
| `/autocode-status` | View current factory status and metrics |
| `/autocode-stop` | Gracefully stop the factory |

## Guardrails

- **Immutable files**: Config files, env files, CI workflows, and the manifest itself are never touched
- **PR size limits**: Max 5 files, 200 lines changed per PR
- **Worktree isolation**: Every cycle runs in its own git worktree
- **Auto-revert**: If CI fails after merge, AutoCode reverts its own PR
- **Diminishing returns**: Pauses when improvements plateau

## Configuration

See [docs/customization.md](docs/customization.md) for manifest tuning.

## Examples

- [TypeScript Monorepo](examples/typescript-monorepo.json)
- [Python FastAPI](examples/python-fastapi.json)
- [Rust CLI](examples/rust-cli.json)

## Dogfood Results

First run against [Ghost v2](https://github.com/ajsai47/ghostv2) (TypeScript monorepo, 1005 tests):

| Cycle | Target | Tests Added | Duration | PR |
|-------|--------|-------------|----------|-----|
| 1 | `page-tree.ts` | 69 | ~3 min | [#25](https://github.com/ajsai47/ghostv2/pull/25) |
| 2 | `heuristic-generator.ts` | 79 | ~7 min | [#26](https://github.com/ajsai47/ghostv2/pull/26) |
| 3 | `adaptive-selector.ts` | 27 | ~2 min | [#27](https://github.com/ajsai47/ghostv2/pull/27) |

**175 tests shipped across 3 PRs, 100% success rate, Level 1 → Level 2 after 3 consecutive wins.**

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with auto-accept enabled
- Git repository with existing test infrastructure
- No dependencies, no build step — pure Claude Code skill files

## License

MIT
