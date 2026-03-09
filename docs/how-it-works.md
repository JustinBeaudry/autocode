# How AutoCode Works

## The Loop

AutoCode runs a continuous cycle of work, inspired by [Karpathy's autoresearch](https://x.com/karpathy/status/1886192184808149383) pattern. Each cycle:

1. **Select** a work item from the unified work queue
2. **Route** the pipeline configuration based on work type
3. **Scout** gathers context (read-only exploration — skipped at Level 1-2)
4. **Architect** designs a spec (what to change and why — skipped at Level 1-2)
5. **Builder** implements the change (source + tests)
6. **Tester** adds coverage (test files only — skipped at Level 1-2 for pure functions)
7. **Reviewer** gates quality (approve or reject)
8. **Ship** the PR (commit, push, create PR)
9. **Monitor** CI after merge (auto-revert on failure)
10. **Learn** from the result (update memory)

### Work Queue

Before each cycle, the orchestrator builds a unified work queue from multiple sources:

1. **Focus overrides** (`.autocode/focus`) — user-specified priorities, always first
2. **PR review feedback** — unblock existing PRs before creating new ones
3. **GitHub Issues** — issues labeled `autocode` are parsed by type (bug, feature, refactor, docs)
4. **Coverage gaps** — from the manifest, filtered by failure history and skip rules
5. **Backlog** (`.autocode/backlog.md`) — manually defined tasks
6. **Tech debt signals** — TODO/FIXME comments in source files (optional)

Each source produces typed work items (`coverage`, `feature`, `bugfix`, `refactor`, `docs`, `dependency`, `review_response`). Items are prioritized: focus > reviews > critical bugs > features/coverage > tech debt.

The failure memory system still applies — files with 3+ failures are skipped, recently attempted files are on cooldown, and files with `PERMANENT SKIP` markers are always skipped.

### Pipeline Routing

Different work types use different pipeline configurations:

| Type | Scout | Architect | Builder | Tester | Reviewer |
|------|-------|-----------|---------|--------|----------|
| `coverage` (L1-2) | inline | skip | yes | skip | yes |
| `coverage` (L3+) | yes | yes | yes | yes | yes |
| `feature` | yes | yes | yes | yes | yes |
| `bugfix` | yes | optional | yes | yes | yes |
| `refactor` | yes | yes | yes | yes | yes |
| `docs` | yes | skip | yes | skip | skip |
| `dependency` | skip | skip | yes | yes | yes |
| `review_response` | skip | skip | yes | yes | yes |

This routing ensures each work type gets the right level of analysis without wasting agent spawns.

### The Rejection Loop

The Reviewer is the quality gate. On **APPROVE**, the PR is shipped. On **REJECT**, the Builder gets one retry:

1. The Reviewer's structured feedback is parsed
2. A retry prompt is constructed with the original task, the Builder's previous implementation, and the Reviewer's specific feedback
3. The Builder re-implements in the same worktree
4. If the Builder's retry succeeds, the full pipeline re-runs: tests, Tester (if applicable), then a second Reviewer pass
5. On **second REJECT**, the cycle is abandoned — both rejection reasons are logged to failures.md

A **hard REJECT** (immutable files modified) is immediate — no retry allowed, even during a retry attempt.

### PR Review Response Loop

When an existing AutoCode PR has unaddressed review comments, the orchestrator creates a `review_response` work item:

1. The review comments are categorized:
   - **Must fix**: bugs, errors, security issues, correctness problems
   - **May skip**: style preferences, naming suggestions, optional improvements
2. The Builder addresses each must-fix comment in the PR's branch
3. The Tester verifies fixes don't break anything
4. A comment is posted to the PR summarizing what was fixed and what was intentionally skipped

This allows AutoCode to iterate on feedback without human intervention.

## Manifest-Driven Architecture

The `autocode.manifest.json` is the system's contract. Generated once by `/autocode-bootstrap`, it captures everything agents need to know:

- **What language and framework** is this project?
- **What commands** run tests, coverage, lint, build?
- **Where are the coverage gaps** and in what priority order?
- **What are the guardrails** — what files are off-limits, what are the size limits?
- **What difficulty level** should agents work at?
- **What work sources** are enabled (coverage gaps, GitHub Issues, backlog, PR reviews, tech debt)?
- **What testing conventions** does the project follow (file patterns, assertion style, test structure)?

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

## Persistent Brain

AutoCode v3 introduces a persistent brain — structured memory that survives across sessions and improves over time.

### Knowledge Graph (`.autocode/memory/knowledge.json`)

A persistent cache of codebase structure. The Scout checks the graph before analyzing any file:

- **Cache hit**: File's SHA hasn't changed since last analysis → skip re-reading, use cached exports, imports, type, complexity
- **Cache miss**: File is new or modified → full analysis, then update the graph

The graph stores per-file data (exports, imports, type, complexity, test file, coverage) and module-level groupings (which files belong to which directory, internal dependencies, dependents). This context is passed to the Architect and Builder for better decision-making.

### Pattern Database (`.autocode/memory/patterns.json`)

Replaces unstructured `lessons.md` with a weighted, indexed pattern database. Each pattern has:

- **Category**: `test_approach`, `mock_strategy`, `error_fix`, `review_pattern`, `human_feedback`
- **Tags**: Language, framework, test runner for matching
- **Weights**: `success_count` and `failure_count` track how often the pattern works
- **Recency**: Patterns decay over time — recent patterns score higher

Before each cycle, the orchestrator queries the top 5 patterns by score:
```
score = (success_count / (success_count + failure_count)) * recency_weight * tag_match_count
```

After each cycle, patterns are created or updated from the result:
- SUCCESS → increment `success_count`
- FAILURE → increment `failure_count`
- REVIEWER REJECT → create `review_pattern` entry

Stale patterns (older than `manifest.brain.pattern_retention_days`, default 90 days) are automatically pruned.

### Human Feedback Loop

Every PR comment from a human is a training signal. After each cycle, the orchestrator checks for human feedback on past AutoCode PRs:

1. Find recently merged/closed PRs with the `autocode` label
2. Filter out bot comments, extract substantive human reviews
3. Create weighted patterns:
   - Merged with positive feedback → high success weight
   - Merged with nits → moderate weight with caution
   - Closed without merge → high failure weight
4. Track which PRs have been ingested in `.autocode/memory/feedback_log.json`

This allows AutoCode to learn from human reviewers and avoid repeating mistakes.

## Memory System

AutoCode maintains per-repo memory in `.autocode/memory/`:

- **fixes.md**: What was successfully changed and how (includes work type for each entry)
- **failures.md**: What was attempted and why it failed (with attempt counts — 3+ triggers automatic skip)
- **velocity.md**: Cycle-by-cycle timing and results (includes work type per cycle for throughput tracking)
- **coverage.md**: Per-file coverage progression over time (real measured deltas, not estimates)
- **lessons.md**: Patterns that work and anti-patterns that don't — kept as human-readable output
- **costs.md**: Per-cycle cost estimates based on model usage, with running totals
- **knowledge.json**: Persistent codebase knowledge graph (see Persistent Brain)
- **patterns.json**: Weighted pattern database (see Persistent Brain)
- **ci_patterns.json**: CI failure patterns and fix history (see CI-Aware Shipping)
- **feedback_log.json**: Tracks which PRs have had human feedback ingested

Before each cycle, the orchestrator:
1. Checks failures memory to avoid retrying known-bad approaches (and skips files with 3+ failures)
2. Queries the pattern database for the top 5 relevant patterns (or falls back to lessons.md if brain is disabled)
3. Passes knowledge graph context to downstream agents

After each cycle, the orchestrator:
1. Updates velocity, coverage, fixes/failures, lessons, patterns, and knowledge graph
2. Ingests human feedback from merged/closed PRs (Step 7b)
3. Prunes stale patterns beyond the retention window

### Lessons Extraction

Lessons are categorized by cycle outcome:

- **On SUCCESS**: Records what approach worked (test patterns, mocking strategy, framework usage) → creates/updates pattern in patterns.json
- **On FAILURE**: Records what to avoid (anti-patterns, reasons for failure) → creates/updates pattern with failure weight
- **On REVIEWER REJECT**: Records quality insights (what the Reviewer caught, how it was fixed) → creates `review_pattern` entry

## Real Coverage Tracking

AutoCode measures actual coverage, not estimates:

1. **Baseline**: Before any changes, the coverage command runs in the worktree to capture the starting point
2. **Post-change**: After the Builder and Tester finish, coverage runs again
3. **Delta**: The orchestrator calculates per-file and overall coverage deltas from measured data
4. **Manifest update**: After each successful cycle, the manifest's `coverage.gaps` array is updated with real coverage numbers — files that exceed targets are removed, priorities are re-sorted

The coverage parser supports v8/istanbul (TypeScript/JavaScript), pytest-cov (Python), tarpaulin (Rust), and go-cover (Go).

## Progressive Difficulty

AutoCode starts with easy wins and graduates to harder tasks:

| Level | Label | Work Types | File Types |
|-------|-------|------------|-----------|
| 1 | Simple tests | `coverage` only | Pure functions |
| 2 | Standard tests | `coverage` only | Pure functions, utilities |
| 3 | Bug fixes | `coverage`, `bugfix` | All file types |
| 4 | Integration work | `coverage`, `bugfix`, `feature` (small) | Services, handlers |
| 5 | Feature work | All except complex refactors | All types |
| 6 | Complex changes | All types | All types |

At Level 3+, AutoCode can pull work from GitHub Issues instead of only coverage gaps. Review responses and focus overrides are always enabled regardless of level.

After 3 consecutive successes at a level, AutoCode advances to the next. After 3 consecutive failures, it drops back one level (minimum level 1). This prevents wasting cycles on tasks that are too hard.

## Stop Conditions

The factory stops when any of these conditions are met (checked in order):

1. **Stop signal**: The user runs `/autocode-stop` (creates `.autocode/STOP` file)
2. **Time budget**: Total session time exceeds `manifest.time_budgets.cycle_max_seconds`
3. **Consecutive failures**: The last 5 velocity entries are all FAILURE — prints failure reasons and suggests lowering difficulty or refreshing targets
4. **Consecutive rejections**: The last 3 cycles were all rejected by the Reviewer — prints rejection feedback summaries and suggests reviewing Reviewer feedback patterns
5. **Diminishing returns**: The last 5 *successful* coverage deltas are all < 0.5% — prints the deltas and suggests advancing difficulty, refreshing gaps, or setting `ignore_diminishing_returns: true` in the manifest to continue. Note: this only applies to `coverage` work items; other work types are not subject to diminishing returns detection.
6. **No more targets**: All coverage gaps have been attempted, skipped, or met their targets

## CI-Aware Shipping

When a PR is auto-merged and CI subsequently fails on the default branch, AutoCode no longer blindly reverts. Instead, it reads the CI logs, categorizes the failure, and attempts to fix it.

### CI Failure Categories

| Category | Signal | Action |
|----------|--------|--------|
| `test_failure` | "FAIL", "AssertionError" | Spawn Builder with `ci_fix` work type |
| `type_error` | "TS2", "TypeError" | Spawn Builder with type error details |
| `lint_error` | "eslint", "pylint", "clippy" | Spawn Builder with lint output |
| `build_error` | "Cannot find module" | Spawn Builder with build error |
| `env_error` | "ECONNREFUSED", "timeout" | Log as infra issue, revert |
| `unknown` | No recognizable pattern | Log and revert |

### Fix Flow

1. Parse CI logs to categorize the failure and extract error context (file paths, line numbers, error messages)
2. Check `.autocode/memory/ci_patterns.json` for known fixes matching the error signature
3. Spawn Builder with `ci_fix` work type — minimal fix, no refactoring
4. Verify fix locally with the test command
5. If fix passes: push, create PR (labeled `autocode`, `ci-fix`), log success
6. If fix fails: retry up to `manifest.ci.max_fix_attempts` (default: 2) with different approach
7. If all attempts fail: revert (v2 behavior)

### CI Pattern Database (`.autocode/memory/ci_patterns.json`)

Tracks CI failure patterns and fix history:
- Each failure records: category, error signature, file, fix applied, whether it worked
- Stats track: total failures, auto-fixed count, reverted count, fix rate
- Known fixes are suggested to the Builder on similar future failures

### Fallback

If `manifest.ci.auto_fix` is false, or if the failure category is `env_error` or `unknown`, AutoCode falls back to the v2 behavior:

1. Creates a revert branch and reverts the merge commit
2. Opens a revert PR with the `autocode` and `revert` labels
3. Logs the regression to `failures.md` with a `CI_REGRESSION` tag
4. Downgrades the difficulty level by 1 (minimum level 1)
5. Resets the consecutive success streak to 0

If CI hasn't completed after 10 minutes, the orchestrator logs a timeout warning and moves on rather than blocking the factory.

## Multi-PR Planning

AutoCode v4 can decompose large tasks into a dependency graph of atomic PRs. Instead of trying to ship "add auth" in one PR, the Planner agent breaks it down:

1. **step_1**: Define auth types and interfaces → PR #30
2. **step_2**: Implement auth middleware (blocked by step_1) → PR #31
3. **step_3**: Add route handlers (blocked by step_2) → PR #32
4. **step_4**: Add tests (blocked by step_2, step_3) → PR #33

### Plan Files

Plans are stored in `.autocode/plans/<plan-id>.json` with a structured dependency graph. Each step has:
- `work_type`: feature, bugfix, refactor, coverage, docs
- `target_files`: what files this step touches
- `blocked_by`: which steps must complete first
- `status`: pending, in_progress, completed, failed

### How Plans Integrate

The orchestrator ingests unblocked plan steps as high-priority work items (above review responses, below focus overrides). When a step completes, the orchestrator updates the plan file. When a step fails, only directly dependent steps are blocked — other branches of the dependency graph continue.

### Creating Plans

Use `/autocode-plan` to decompose a task:
```
/autocode-plan "Add authentication with JWT, middleware, routes, and tests"
/autocode-plan #25  # From a GitHub Issue
```

The Planner agent (read-only) analyzes the task, queries the knowledge graph for codebase structure, and produces a plan for user approval.

When `manifest.planning.auto_plan_issues` is true, large GitHub Issues are automatically decomposed instead of treated as single work items.

## Daemon Mode

AutoCode v4 can run unattended on a schedule via GitHub Actions. Use `/autocode-daemon setup` to generate a workflow file.

### How It Works

1. A GitHub Actions workflow runs on a cron schedule (default: every 6 hours)
2. It restores `.autocode/memory/` from cache for state persistence
3. It checks the daily budget — if exceeded, the run is skipped
4. It runs `/autocode` with a configurable cycle limit
5. It saves state back to cache for the next run
6. On failure, it creates a GitHub Issue for notification

### Budget Controls

The daemon tracks spending in `.autocode/memory/costs.md` and enforces a daily budget (`manifest.daemon.daily_budget_usd`, default: $10/day). When the budget is reached, the daemon stops gracefully. Budget can also be overridden via the `AUTOCODE_DAILY_BUDGET` repository variable.

### Daemon State

`.autocode/daemon_state.json` persists across runs and tracks: last run time, result, cycle count, PRs created, and daily spending. The orchestrator writes this at the end of each daemon run and reads it at the start.

### Deploy Windows

Configure `manifest.daemon.deploy_windows` with cron expressions for times when AutoCode should NOT run (e.g., during scheduled deployments).

## Proactive Discovery

AutoCode v4 can find work that needs doing without being told. The Discoverer agent runs once per session (or daemon run) and scans for:

### Discovery Modules

| Module | What It Finds | Work Type |
|--------|---------------|-----------|
| Untested Changes | Recent commits that modified code without tests | `coverage` |
| Complexity Hotspots | Files above 300 lines with high change frequency | `refactor` |
| Dependency Audit | Known vulnerabilities via npm/pip/cargo audit | `dependency` |
| Stale TODOs | TODO/FIXME comments older than 30 days | `bugfix`/`feature` |

### How Discovery Integrates

1. Discoverer agent runs and returns a list of work items
2. Items are saved to `.autocode/discovery.json`
3. The orchestrator ingests discovery items as a work source (priority 4 — above tech debt, below features)
4. Deduplication prevents the same file from appearing twice in the queue

### Running Discovery Manually

Use `/autocode-discover` to run discovery outside the normal cycle:
```
/autocode-discover          # Run and save results
/autocode-discover --dry    # Preview without saving
/autocode-discover --clear  # Clear discovered items
```

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
