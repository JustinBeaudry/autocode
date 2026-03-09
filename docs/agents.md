# Agent Reference

## Overview

AutoCode uses 5 specialized agents, each with strict constraints on what they can read and write. This constraint system is the core quality mechanism — agents can't step on each other's toes.

All agents reference manifest values directly (e.g., `manifest.commands.coverage`, `manifest.guardrails.immutable_patterns`) rather than using placeholder syntax like `{{variable}}`. This prevents template injection issues and makes prompts self-documenting.

## Agent Details

### Scout

**Role**: Codebase explorer — gathers context for downstream agents.

**File**: `agents/scout.md`

**Can use**: Read, Glob, Grep, Bash (read-only commands)
**Cannot use**: Write, Edit, NotebookEdit

**Input**:
- Target file path
- Manifest contents
- Previous failure memory

**Output**: Structured context report including:
- File analysis (exports, functions, classes)
- Existing test coverage
- Dependency graph
- Project testing patterns
- Previous failure notes
- Recommendations

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

**Output**: Test result (SUCCESS/FAILURE) including:
- Tests written
- Coverage before/after/delta
- Mutation testing results
- Test output

**Model**: Sonnet (default via `manifest.model_routing.tester`)

**Skipped at Level 1-2 for pure functions**: The Builder already writes comprehensive tests for simple coverage work. Tester is spawned at Level 3+, or when the Builder made source code changes (not just test files).

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

**Model**: Opus (default via `manifest.model_routing.reviewer`)

**Time budget**: 300 seconds (default)

## Agent Communication Flow

```
Orchestrator
    |
    |--- [Select target + parse failure memory]
    |
    |--- Scout (L3+ only) -----.
    |    (context report)       |
    |                           v
    |--- Architect (L3+ only) <-- Scout's context
    |    (spec)                 |
    |                           v
    |--- Builder <-- Architect's spec (L3+) or inline context (L1-2)
    |    (implementation)       |         + failure context + lessons
    |                           v
    |--- Tester (L3+ or src changes) <-- Builder's changes
    |    (additional tests)     |
    |                           v
    |--- Reviewer <-- Full diff + Builder result + Tester result
    |    (verdict)
    |         |
    |         |--- APPROVE --> Ship PR --> Monitor CI
    |         |
    |         |--- REJECT (1st) --> Builder retry (same worktree)
    |         |                         |
    |         |                         v
    |         |                     Re-run tests --> [Re-run Tester] --> Reviewer (2nd)
    |         |                                                             |
    |         |                                           APPROVE ----------+---> Ship PR
    |         |                                           REJECT (2nd) -----+---> Abandon
    |         |
    |         |--- HARD REJECT (immutable violation) --> Abandon immediately
    |
    |--- [Update memory: velocity, coverage, fixes/failures, lessons, costs]
    |
    |--- [Clean up worktree]
    |
    v
  Check stop conditions --> next cycle or stop
```

Each agent receives the output of the previous agent in the chain. The Orchestrator manages the handoffs and handles failures at each stage. Lesson memory is injected into Builder prompts (the 5 most recent relevant lessons, matched by file type and testing patterns).
