# Agent Reference

## Overview

AutoCode uses 5 specialized agents, each with strict constraints on what they can read and write. This constraint system is the core quality mechanism — agents can't step on each other's toes.

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

**Model**: Haiku (fast, cheap — this is a read-heavy task)

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
- Detailed test cases (input → expected output)
- Mocking requirements
- Acceptance criteria
- Risks

**Model**: Sonnet (mid-weight reasoning)

**Time budget**: 180 seconds (default)

---

### Builder

**Role**: Implementer — writes source code and tests.

**File**: `agents/builder.md`

**Can use**: Read, Glob, Grep, Bash, Write, Edit
**Cannot use**: Modifying immutable files

**Input**:
- Target file path
- Scout's context or Architect's spec
- Manifest contents
- Worktree path
- Difficulty level

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

**Model**: Opus (complex judgment required)

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

**Model**: Sonnet (test writing is structured)

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
- Tester's result

**Output**: Verdict (APPROVE/REJECT) including:
- Review checklist results (correctness, safety, scope, quality, test quality)
- Feedback (if rejected — must be actionable)
- Suggested PR title and body (if approved)

**Rules**:
- Hard reject if immutable files are modified
- One retry allowed on soft rejection
- Feedback must be specific and actionable

**Model**: Opus (quality judgment is critical)

**Time budget**: 300 seconds (default)

## Agent Communication Flow

```
Orchestrator
    │
    ├─── Scout ────────────────────┐
    │    (context report)          │
    │                              ▼
    ├─── Architect ◄── Scout's context
    │    (spec)                    │
    │                              ▼
    ├─── Builder ◄── Architect's spec
    │    (implementation)          │
    │                              ▼
    ├─── Tester ◄── Builder's changes
    │    (additional tests)        │
    │                              ▼
    └─── Reviewer ◄── Full diff
         (verdict)
```

Each agent receives the output of the previous agent in the chain. The Orchestrator manages the handoffs and handles failures at each stage.
