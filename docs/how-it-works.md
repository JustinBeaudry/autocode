# How AutoCode Works

## The Loop

AutoCode runs a continuous cycle of work, inspired by [Karpathy's autoresearch](https://x.com/karpathy/status/1886192184808149383) pattern. Each cycle:

1. **Select** a target (lowest-coverage file not recently attempted)
2. **Scout** gathers context (read-only exploration)
3. **Architect** designs a spec (what to change and why)
4. **Builder** implements the change (source + tests)
5. **Tester** adds coverage (test files only)
6. **Reviewer** gates quality (approve or reject)
7. **Ship** the PR (commit, push, create PR)
8. **Learn** from the result (update memory)

## Manifest-Driven Architecture

The `autocode.manifest.json` is the system's contract. Generated once by `/autocode-bootstrap`, it captures everything agents need to know:

- **What language and framework** is this project?
- **What commands** run tests, coverage, lint, build?
- **Where are the coverage gaps** and in what priority order?
- **What are the guardrails** — what files are off-limits, what are the size limits?
- **What difficulty level** should agents work at?

Agents don't discover — they read the manifest. This prevents wasted cycles re-analyzing the same project structure.

## Constrained Agents

Each agent has strict boundaries:

### Scout (Read-Only)
The Scout explores the codebase but cannot change anything. It reads the target file, finds existing tests, identifies dependencies, and checks testing patterns. Its output is a context report.

### Architect (Spec-Only)
The Architect receives the Scout's context and produces a specification — no code. The spec describes exactly what to change, what tests to write, and what edge cases to cover.

### Builder (Source Files)
The Builder implements the Architect's spec. It can create and modify source files and test files within the guardrails (max files, max lines). It runs the test suite to verify.

### Tester (Test Files Only)
The Tester adds additional test coverage after the Builder's changes. It can only touch test files. It runs coverage to measure improvement.

### Reviewer (Nothing)
The Reviewer reads the complete diff and makes a verdict: APPROVE or REJECT. On rejection, the Builder gets one retry with structured feedback. On second rejection, the cycle is abandoned.

## Worktree Isolation

Every cycle runs in its own git worktree — a separate working directory on a separate branch. This means:

- The main working tree stays clean
- Multiple cycles can run in parallel without conflicts
- Failed cycles are cleaned up without affecting other work
- Each cycle gets a fresh branch name

## Memory System

AutoCode maintains per-repo memory in `.autocode/memory/`:

- **fixes.md**: What was successfully changed and how
- **failures.md**: What was attempted and why it failed
- **velocity.md**: Cycle-by-cycle timing and results
- **coverage.md**: Per-file coverage progression over time
- **lessons.md**: Patterns that work and patterns that don't

Before each cycle, the orchestrator checks failures memory to avoid retrying known-bad approaches. After each cycle, it updates the relevant memory files.

## Progressive Difficulty

AutoCode starts with easy wins and graduates to harder tasks:

| Level | Description | What It Means |
|-------|-------------|---------------|
| 1 | Pure function coverage | Test functions with no side effects — just input → output |
| 2 | Utility/helper coverage | Test utilities that may need light mocking |
| 3 | Fix failing tests | Make existing broken tests pass |
| 4 | Integration coverage | Test code with DB, API, or service interactions |
| 5 | Feature implementation | Implement features from tickets/specs |
| 6 | Refactoring | Restructure code while preserving behavior |

After 3 consecutive successes at a level, AutoCode advances to the next. After 3 consecutive failures, it drops back one level. This prevents wasting cycles on tasks that are too hard.

## Stop Conditions

The factory stops when:
- The user runs `/autocode-stop`
- All coverage gaps have been attempted
- 5 consecutive cycles have failed
- The last 5 coverage improvements were each < 0.5% (diminishing returns)
- The time budget is exceeded

## Cost Considerations

AutoCode is designed to be cost-efficient:
- Scout and Tester use Haiku/Sonnet (cheap, fast models)
- Builder and Reviewer use Opus (expensive but necessary for quality)
- Small PR sizes mean shorter agent sessions
- Progressive difficulty means early cycles are cheap and fast
- Memory prevents retrying expensive failures
