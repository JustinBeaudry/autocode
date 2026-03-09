# How AutoCode Works

## The Loop

AutoCode runs a continuous cycle of work, inspired by [Karpathy's autoresearch](https://x.com/karpathy/status/1886192184808149383) pattern. Each cycle:

1. **Select** a target (lowest-coverage file, filtered by failure history and skip rules)
2. **Scout** gathers context (read-only exploration — skipped at Level 1-2)
3. **Architect** designs a spec (what to change and why — skipped at Level 1-2)
4. **Builder** implements the change (source + tests)
5. **Tester** adds coverage (test files only — skipped at Level 1-2 for pure functions)
6. **Reviewer** gates quality (approve or reject)
7. **Ship** the PR (commit, push, create PR)
8. **Monitor** CI after merge (auto-revert on failure)
9. **Learn** from the result (update memory)

### Target Selection and Failure Memory

Before selecting a target, the orchestrator parses `.autocode/memory/failures.md` to build a failure map. For each file, it counts attempts and checks for skip markers. The skip rules are applied in order:

1. **Permanent skip**: File has a `PERMANENT SKIP` marker — always skipped
2. **Too many failures**: File has 3+ total failure attempts — skipped (too hard at current level)
3. **Cooldown**: File was attempted in the last 2 cycles — skipped
4. **Immutable**: File matches an immutable pattern — skipped
5. **Difficulty mismatch**: File doesn't match the current difficulty level — skipped

If the selected target has 1-2 previous failures, the failure details are extracted and injected into the Builder prompt so it avoids repeating failed approaches.

### The Rejection Loop

The Reviewer is the quality gate. On **APPROVE**, the PR is shipped. On **REJECT**, the Builder gets one retry:

1. The Reviewer's structured feedback is parsed
2. A retry prompt is constructed with the original task, the Builder's previous implementation, and the Reviewer's specific feedback
3. The Builder re-implements in the same worktree
4. If the Builder's retry succeeds, the full pipeline re-runs: tests, Tester (if applicable), then a second Reviewer pass
5. On **second REJECT**, the cycle is abandoned — both rejection reasons are logged to failures.md

A **hard REJECT** (immutable files modified) is immediate — no retry allowed, even during a retry attempt.

## Manifest-Driven Architecture

The `autocode.manifest.json` is the system's contract. Generated once by `/autocode-bootstrap`, it captures everything agents need to know:

- **What language and framework** is this project?
- **What commands** run tests, coverage, lint, build?
- **Where are the coverage gaps** and in what priority order?
- **What are the guardrails** — what files are off-limits, what are the size limits?
- **What difficulty level** should agents work at?

Agents reference manifest values directly (e.g., `manifest.commands.coverage`, `manifest.guardrails.immutable_patterns`) rather than using placeholder syntax. This prevents template injection issues and makes agent prompts self-documenting.

## Constrained Agents

Each agent has strict boundaries:

### Scout (Read-Only)
The Scout explores the codebase but cannot change anything. It reads the target file, finds existing tests, identifies dependencies, and checks testing patterns. Its output is a context report. At Level 1-2, the orchestrator skips spawning a separate Scout agent and gathers context inline to save an agent spawn (~30s).

### Architect (Spec-Only)
The Architect receives the Scout's context and produces a specification — no code. The spec describes exactly what to change, what tests to write, and what edge cases to cover. At Level 1-2, the Architect is skipped — the Builder works from Scout context directly.

### Builder (Source Files)
The Builder implements the Architect's spec. It can create and modify source files and test files within the guardrails (max files, max lines). It runs the test suite to verify.

### Tester (Test Files Only)
The Tester adds additional test coverage after the Builder's changes. It can only touch test files. It runs coverage to measure improvement. At Level 1-2 with pure functions, the Tester is skipped — the Builder already writes comprehensive tests for simple coverage work.

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
- **failures.md**: What was attempted and why it failed (with attempt counts — 3+ triggers automatic skip)
- **velocity.md**: Cycle-by-cycle timing and results
- **coverage.md**: Per-file coverage progression over time (real measured deltas, not estimates)
- **lessons.md**: Patterns that work and anti-patterns that don't — extracted after every cycle and injected into future Builder prompts
- **costs.md**: Per-cycle cost estimates based on model usage, with running totals

Before each cycle, the orchestrator:
1. Checks failures memory to avoid retrying known-bad approaches (and skips files with 3+ failures)
2. Extracts relevant lessons (matching file type, test framework, module type) and injects them into Builder prompts

After each cycle, the orchestrator:
1. Updates velocity, coverage, fixes/failures, and lessons
2. Deduplicates lessons — if the same pattern already exists, it updates the timestamp rather than adding a duplicate

### Lessons Extraction

Lessons are categorized by cycle outcome:

- **On SUCCESS**: Records what approach worked (test patterns, mocking strategy, framework usage)
- **On FAILURE**: Records what to avoid (anti-patterns, reasons for failure)
- **On REVIEWER REJECT**: Records quality insights (what the Reviewer caught, how it was fixed)

## Real Coverage Tracking

AutoCode measures actual coverage, not estimates:

1. **Baseline**: Before any changes, the coverage command runs in the worktree to capture the starting point
2. **Post-change**: After the Builder and Tester finish, coverage runs again
3. **Delta**: The orchestrator calculates per-file and overall coverage deltas from measured data
4. **Manifest update**: After each successful cycle, the manifest's `coverage.gaps` array is updated with real coverage numbers — files that exceed targets are removed, priorities are re-sorted

The coverage parser supports v8/istanbul (TypeScript/JavaScript), pytest-cov (Python), tarpaulin (Rust), and go-cover (Go).

## Progressive Difficulty

AutoCode starts with easy wins and graduates to harder tasks:

| Level | Description | What It Means |
|-------|-------------|---------------|
| 1 | Pure function coverage | Test functions with no side effects — just input -> output |
| 2 | Utility/helper coverage | Test utilities that may need light mocking |
| 3 | Fix failing tests | Make existing broken tests pass |
| 4 | Integration coverage | Test code with DB, API, or service interactions |
| 5 | Feature implementation | Implement features from tickets/specs |
| 6 | Refactoring | Restructure code while preserving behavior |

After 3 consecutive successes at a level, AutoCode advances to the next. After 3 consecutive failures, it drops back one level (minimum level 1). This prevents wasting cycles on tasks that are too hard.

## Stop Conditions

The factory stops when any of these conditions are met (checked in order):

1. **Stop signal**: The user runs `/autocode-stop` (creates `.autocode/STOP` file)
2. **Time budget**: Total session time exceeds `manifest.time_budgets.cycle_max_seconds`
3. **Consecutive failures**: The last 5 velocity entries are all FAILURE — prints failure reasons and suggests lowering difficulty or refreshing targets
4. **Consecutive rejections**: The last 3 cycles were all rejected by the Reviewer — prints rejection feedback summaries and suggests reviewing Reviewer feedback patterns
5. **Diminishing returns**: The last 5 *successful* coverage deltas are all < 0.5% — prints the deltas and suggests advancing difficulty, refreshing gaps, or setting `ignore_diminishing_returns: true` in the manifest to continue
6. **No more targets**: All coverage gaps have been attempted, skipped, or met their targets

## Auto-Revert

When a PR is auto-merged and CI subsequently fails on the default branch, AutoCode automatically:

1. Creates a revert branch and reverts the merge commit
2. Opens a revert PR with the `autocode` and `revert` labels
3. Logs the regression to `failures.md` with a `CI_REGRESSION` tag
4. Downgrades the difficulty level by 1 (minimum level 1) — a CI regression means the quality bar needs to be higher
5. Resets the consecutive success streak to 0

If CI hasn't completed after 10 minutes, the orchestrator logs a timeout warning and moves on rather than blocking the factory.

## Manifest Auto-Refresh

Every 10 successful cycles, the orchestrator re-runs the coverage command on the main worktree to refresh the manifest's gap data:

- Files that now exceed all coverage targets are removed from the gaps array
- Coverage percentages for remaining files are updated with real measurements
- New source files that appeared since bootstrap (and have coverage below targets) are added
- Generated files, test files, type definitions, and config files are excluded
- Gaps are re-sorted by coverage (ascending) and re-numbered

This prevents the factory from working off stale data as coverage improves over time.

## Parallel Mode

When run with `--parallel N` (or `"parallel": N` in the manifest), AutoCode runs N pipelines simultaneously:

1. A work queue is built from the top N x 2 candidates (for replacements)
2. A dependency conflict graph prevents parallel work on files that share imports
3. N non-conflicting targets are selected and each gets its own worktree
4. All pipelines run the full cycle independently (Scout -> Architect -> Builder -> Tester -> Reviewer)
5. Memory updates are batched — all writes happen after all pipelines complete to prevent write conflicts

Maximum 5 parallel pipelines. Default is 1 (sequential).

## Cost Tracking

AutoCode tracks per-cycle cost estimates based on model usage:

- Each agent's model (Sonnet vs Opus) contributes to the cycle cost
- Running totals accumulate in `.autocode/memory/costs.md`
- The cycle summary shows cost for the current cycle
- Status dashboard shows total cost, cost per PR, and cost per coverage point

This helps teams understand the ROI of automated coverage work and set budgets appropriately.

## Cost Considerations

AutoCode is designed to be cost-efficient:
- Scout and Tester use Sonnet (balanced cost/reliability)
- Builder and Reviewer use Opus (expensive but necessary for quality)
- At Level 1-2, Scout, Architect, and Tester are skipped — reducing per-cycle cost significantly
- Small PR sizes mean shorter agent sessions
- Progressive difficulty means early cycles are cheap and fast
- Memory prevents retrying expensive failures
- Diminishing returns detection prevents wasting money on marginal improvements
