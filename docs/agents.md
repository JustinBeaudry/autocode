# Agent Reference

## Overview

AutoCode uses 7 specialized agents, each with strict constraints on what they can read and write. This constraint system is the core quality mechanism — agents can't step on each other's toes.

All agents reference manifest values directly (e.g., `manifest.commands.coverage`, `manifest.guardrails.immutable_patterns`) rather than using placeholder syntax like `{{variable}}`. This prevents template injection issues and makes prompts self-documenting.

## Agent Details

### Scout

**Role**: Codebase explorer — gathers context for downstream agents.

**File**: `agents/scout.md`

**Can use**: Read, Glob, Grep, Bash (read-only commands)
**Cannot use**: Write, Edit, NotebookEdit

**Input**:
- Work item (type, description, target files, source)
- Manifest contents
- Previous failure memory
- Knowledge graph (`.autocode/memory/knowledge.json`) — for cache checks

**Output**: Structured context report including:
- File analysis (exports, functions, classes) — from cache or fresh analysis
- Existing test coverage
- Dependency graph
- Project testing patterns
- Previous failure notes
- Work item context (type, source, scope, related files)
- Knowledge graph context (module groupings, dependency relationships)
- Knowledge graph updates (new/updated file entries for the orchestrator to merge)
- Recommendations

**Knowledge Graph Integration**: Before analyzing any file, the Scout checks `knowledge.json` for cached data. If the file's SHA hasn't changed since last analysis (cache hit), it skips re-reading the file's structure and uses cached exports, imports, type, and complexity. On cache miss, it does full analysis and returns updated entries for the orchestrator to merge.

**Model**: Sonnet (default via `manifest.model_routing.scout`). Note: avoid Haiku — it fails on repos with many MCP tools due to schema size limits. Sonnet is the safe default.

**Skipped at Level 1-2**: The orchestrator gathers context inline instead of spawning a separate Scout agent. At these levels, the Builder reads the same files anyway, so spawning a Scout would waste ~30 seconds. Scout is spawned at Level 3+.

**Time budget**: 180 seconds (default)

---

### Architect

**Role**: Solution designer — produces specs, not code.

**File**: `agents/architect.md`

**Can use**: Read, Glob, Grep, Bash (read-only commands)
**Cannot use**: Write, Edit, NotebookEdit

**Input**:
- Target file path
- Scout's context report
- Manifest contents
- Current difficulty level

**Output**: Structured specification including:
- Target functions to cover/modify
- Approach description
- Files to modify/create
- Detailed test cases (input -> expected output)
- Mocking requirements
- Acceptance criteria
- Risks

**Model**: Sonnet (default via `manifest.model_routing.architect`)

**Skipped at Level 1-2**: Simple coverage work doesn't need a spec. The Builder works from Scout context (or inline context) directly. Architect is spawned at Level 3+.

**Lessons**: Receives relevant lessons from previous cycles (matching file type, test framework, module type). Success patterns should be replicated; failure anti-patterns should be avoided.

**Time budget**: 180 seconds (default)

---

### Builder

**Role**: Implementer — writes source code and tests.

**File**: `agents/builder.md`

**Can use**: Read, Glob, Grep, Bash, Write, Edit
**Cannot use**: Modifying immutable files

**Input**:
- Target file path
- Inline Scout context (L1-2) or Architect's spec (L3+)
- Manifest contents
- Worktree path
- Difficulty level
- Failure context (if target has 1-2 previous failures — describes failed approaches to avoid)
- Relevant lessons from `.autocode/memory/lessons.md` (matched by file type, test framework, module type)
- Work type guidance (type-specific instructions: bugfix, feature, refactor, docs, dependency, review_response)

**Output**: Implementation result (SUCCESS/FAILURE) including:
- Files changed with descriptions
- Tests added
- Test output
- Coverage delta
- Notes

**Rules**:
- Max 3 retry attempts on test failures
- Must follow project conventions
- Cannot add new dependencies
- Cannot exceed file/line change limits

**Work Types**: The Builder handles different work types with type-specific guidance:
- `bugfix`: Write failing test first, then fix
- `feature`: Follow Architect spec, implement incrementally
- `refactor`: Verify tests before AND after changes
- `docs`: Documentation only, no source changes
- `dependency`: Update versions, fix breaking changes
- `review_response`: Address review comments, commit as fixups
- `ci_fix`: Fix CI failures with minimal changes — read error output, fix the source, don't refactor

**On Reviewer rejection**: Gets one retry with structured feedback. The retry prompt includes the original task, previous implementation summary, and the Reviewer's specific feedback. The Builder works in the same worktree (not a new one).

**Model**: Opus (default via `manifest.model_routing.builder`). Falls back to Sonnet if the specified model fails with an API error.

**Time budget**: 600 seconds (default)

---

### Tester

**Role**: Test writer — adds coverage after Builder's changes.

**File**: `agents/tester.md`

**Can use**: Read, Glob, Grep, Bash, Write, Edit (test files only)
**Cannot use**: Modifying source files

**Input**:
- Target file path
- Builder's change summary
- Scout's context report
- Manifest contents
- Worktree path
- Architect's specification (if available) — for edge case and acceptance criteria coverage

**Output**: Test result (SUCCESS/FAILURE) including:
- Tests written
- Coverage before/after/delta
- Mutation testing results
- Test output

**Model**: Sonnet (default via `manifest.model_routing.tester`)

**Skipped at Level 1-2 for pure functions**: The Builder already writes comprehensive tests for simple coverage work. Tester is spawned at Level 3+, or when the Builder made source code changes (not just test files).

**Lessons**: Receives relevant lessons from previous cycles. Uses them to replicate successful testing patterns and avoid approaches that failed before.

**Time budget**: 600 seconds (default)

---

### Reviewer

**Role**: Quality gate — approves or rejects changes.

**File**: `agents/reviewer.md`

**Can use**: Read, Glob, Grep, Bash (read-only commands)
**Cannot use**: Write, Edit, NotebookEdit

**Input**:
- Worktree path
- Manifest contents
- Scout's context report
- Builder's result
- Tester's result (if applicable)
- Architect's specification (if available) — for spec compliance checking

**Output**: Verdict (APPROVE/REJECT) including:
- Review checklist results (correctness, safety, scope, quality, test quality)
- Feedback (if rejected — must be actionable)
- Suggested PR title and body (if approved)

**Rules**:
- Hard reject if immutable files are modified (no retry allowed, even during a retry attempt)
- One retry allowed on soft rejection — Builder gets structured feedback
- On second rejection, cycle is abandoned and both rejection reasons are logged
- Feedback must be specific and actionable

**On retry review**: The Reviewer receives a flag indicating this is a retry, along with the original feedback. It verifies that every item in the original feedback was addressed. Partial fixes result in a second REJECT.

**Spec Compliance**: When an Architect spec is provided, the Reviewer validates that the implementation matches the specification, all acceptance criteria are met, and specified edge cases are covered in tests.

**Lessons**: Receives relevant lessons from previous cycles. Watches for recurring quality issues from previous reviews.

**Model**: Opus (default via `manifest.model_routing.reviewer`)

**Time budget**: 300 seconds (default)

### Planner

**Role**: Task decomposer — takes a large task and produces a dependency graph of atomic PRs.

**File**: `agents/planner.md`

**Can use**: Read, Glob, Grep, Bash (read-only commands)
**Cannot use**: Write, Edit, NotebookEdit

**Input**:
- Task description (from GitHub Issue body, focus item, or user prompt)
- Manifest contents
- Knowledge graph (`.autocode/memory/knowledge.json`)
- Pattern database (top relevant patterns from `.autocode/memory/patterns.json`)

**Output**: Structured plan JSON with:
- Plan metadata (id, title, source, reference)
- Steps array with dependency graph (`blocked_by` relationships)
- Each step specifies: work_type, target_files, description, acceptance criteria

**Quality rules**:
- Each step must be independently shippable and testable
- Each step must be within the guardrails (max files per PR, max lines)
- Steps ordered from foundational (types, interfaces) to dependent (implementations, tests)
- No circular dependencies
- Total steps <= `manifest.planning.max_steps_per_plan`

**Model**: Sonnet (default via `manifest.model_routing.architect`)

**Invoked by**: `/autocode-plan` command

---

### Discoverer

**Role**: Proactive codebase analyst — finds work that needs doing without being told.

**File**: `agents/discoverer.md`

**Can use**: Read, Glob, Grep, Bash (read-only commands like `git log`, `git blame`, `npm audit`, `pip-audit`, `cargo audit`)
**Cannot use**: Write, Edit, NotebookEdit

**Input**:
- Manifest contents
- Discovery configuration (`manifest.discovery`)
- Summary of existing work queue items (for deduplication)
- Previous discovery items (`.autocode/discovery.json`)

**Output**: JSON result with discovered work items, each containing:
- Work type, priority, target files, description, source module, reference

**Discovery modules**:
- **Untested Changes**: Detects recent commits that modified code without corresponding tests
- **Complexity Hotspots**: Finds files above the complexity threshold with high change frequency
- **Dependency Audit**: Checks for known vulnerabilities via `npm audit`, `pip-audit`, `cargo audit`, or `govulncheck`
- **Stale TODOs**: Finds TODO/FIXME/HACK/XXX comments older than the configured threshold

**Deduplication**: Skips items whose target files are already in the work queue from another source.

**Model**: Sonnet (default via `manifest.model_routing.scout`)

**Invoked by**: `/autocode-discover` command, or automatically at session start when `manifest.discovery.enabled` is true

---

## Agent Communication Flow

```
Orchestrator
    |
    |--- [Run Discovery (if enabled, once per session)]
    |--- [Build work queue (focus, plans, issues, gaps, backlog, discovery, reviews, tech debt)]
    |--- [Prioritize and select work item]
    |--- [Route: configure pipeline per work type]
    |
    |--- Scout (if enabled) -----.
    |    (context report)         |
    |                             v
    |--- Architect (if enabled) <-- Scout's context + work item
    |    (spec)                   |
    |                             v
    |--- Builder <-- Architect's spec (or inline context)
    |    (implementation)         |         + failure context + lessons + work type guidance
    |                             v
    |--- Tester (if enabled) <-- Builder's changes + Architect spec
    |    (additional tests)       |
    |                             v
    |--- Reviewer (if enabled) <-- Full diff + Builder + Tester + Architect spec
    |    (verdict)
    |         |
    |         |--- APPROVE --> Ship PR (or update existing PR for review_response)
    |         |
    |         |--- REJECT (1st) --> Builder retry
    |         |                         |
    |         |                         v
    |         |                     Re-run pipeline --> Reviewer (2nd)
    |         |
    |         |--- HARD REJECT --> Abandon immediately
    |
    |--- [Update memory: velocity, coverage, fixes/failures, lessons, costs, patterns, knowledge graph]
    |
    |--- [Update plan status (if work item came from a plan)]
    |
    |--- [Update daemon state (if running in daemon mode)]
    |
    |--- [Ingest human feedback from merged/closed PRs (Step 7b)]
    |
    |--- [Clean up worktree]
    |
    v
  Check stop conditions --> next cycle or stop
```

Each agent receives the output of the previous agent in the chain. The Orchestrator manages the handoffs and handles failures at each stage. Pattern memory is injected into Builder prompts (the top 5 patterns by score from patterns.json, matched by file type, work type, and language). Knowledge graph context from the Scout is also passed to downstream agents for better decision-making.

The Planner and Discoverer agents operate outside the main pipeline — the Planner is invoked by `/autocode-plan` to decompose tasks, and the Discoverer runs at session start (when enabled) to find new work items.
