# AutoCode — Sprint Backlog

## Status Key
- `[ ]` — Todo
- `[~]` — In Progress
- `[x]` — Done

---

## P0 — Complete the Core Pipeline

The orchestrator currently runs Scout → Builder → Ship. The full pipeline needs all 5 agents wired in with the rejection loop.

### AC-01: Wire Reviewer gate into orchestrator
**Priority**: P0 | **Files**: `commands/autocode.md`
**Description**: Add Step 5.5 between Verify and Ship. After Builder succeeds and tests pass, spawn a Reviewer agent. On APPROVE → proceed to Ship. On REJECT → pass feedback to Builder for one retry. On second REJECT → log failure, abandon cycle.
**Acceptance Criteria**:
- Reviewer agent spawned with worktree path, manifest, builder result
- APPROVE verdict → PR created with Reviewer's suggested title/body
- REJECT verdict → Builder re-spawned with structured feedback
- Second REJECT → cycle abandoned, failure logged to memory
- Hard reject (immutable files touched) → immediate abandon, no retry

### AC-02: Wire Architect into orchestrator at Level 3+
**Priority**: P0 | **Files**: `commands/autocode.md`
**Description**: At Level 3+, add a step between Scout and Builder. Spawn Architect agent with Scout's context. Architect returns a spec. Builder receives the spec instead of raw context. This produces higher-quality implementations for harder tasks.
**Acceptance Criteria**:
- Architect spawned at Level 3+ with Scout context, manifest, difficulty level
- Architect's spec passed to Builder as `context`
- At Level 1-2, Architect is skipped (current behavior preserved)
- Model routing respected (manifest.model_routing.architect)

### AC-03: Wire Tester agent into orchestrator
**Priority**: P0 | **Files**: `commands/autocode.md`
**Description**: After Builder succeeds, spawn Tester agent in the same worktree. Tester writes additional test coverage (test files only). This runs BEFORE the Reviewer, so the Reviewer sees the complete diff (source + additional tests).
**Acceptance Criteria**:
- Tester spawned after Builder SUCCESS, before Reviewer
- Tester works in same worktree, can only modify test files
- Tester result (coverage delta) included in Reviewer input
- If Tester fails (tests break), Builder gets one fix attempt
- At Level 1-2 with simple targets, Tester can be skipped (Builder already writes tests)

### AC-04: Implement the rejection loop
**Priority**: P0 | **Files**: `commands/autocode.md`
**Description**: When Reviewer REJECTs, the orchestrator must: (1) parse the Reviewer's structured feedback, (2) re-spawn Builder with the feedback appended to the original prompt, (3) re-run Tester if applicable, (4) re-run Reviewer. Max 1 retry. Track retry count in cycle summary.
**Acceptance Criteria**:
- Reviewer feedback parsed and passed to Builder retry prompt
- Builder retry works in the same worktree (not a new one)
- After retry, full pipeline re-runs (Tester → Reviewer)
- Second REJECT → abandon, log to failures.md with both rejection reasons
- Cycle summary shows retry count

---

## P1 — Memory System

Memory is written but barely consumed. Agents need to read and learn from past cycles.

### AC-05: Consume failures memory to prevent retries
**Priority**: P1 | **Files**: `commands/autocode.md`
**Description**: Before selecting a target in Step 1, parse `.autocode/memory/failures.md` and build a skip list. Skip files with 3+ failures OR files with a "PERMANENT SKIP" marker. Pass relevant failure context to Scout/Builder so they avoid the same approach.
**Acceptance Criteria**:
- Failures.md parsed before target selection
- Files with 3+ failures skipped
- "PERMANENT SKIP" marker respected
- When a target has 1-2 previous failures, the failure context is included in the Builder prompt
- Skip list logged in cycle summary

### AC-06: Lessons memory — extract and consume patterns
**Priority**: P1 | **Files**: `commands/autocode.md`, `agents/builder.md`
**Description**: After each cycle, extract lessons: what patterns worked, what mocking approaches succeeded, what test styles passed review. Write to `.autocode/memory/lessons.md`. Before each cycle, read lessons and include relevant ones in Builder/Tester prompts.
**Acceptance Criteria**:
- Lessons extracted from successful cycles (test patterns, mocking approaches, file structures)
- Lessons from failures extracted (what approaches to avoid)
- Builder prompt includes top 5 relevant lessons
- Lessons deduplicated (don't repeat the same lesson)

### AC-07: Coverage tracking with real data
**Priority**: P1 | **Files**: `commands/autocode-bootstrap.md`, `commands/autocode.md`
**Description**: Bootstrap already installs coverage tooling. The orchestrator should run coverage before AND after each cycle, parse the output, and track real deltas per-file. Update `.autocode/memory/coverage.md` with actual numbers. Update manifest's `coverage.gaps` after each cycle.
**Acceptance Criteria**:
- Coverage command run before cycle (baseline) and after (result)
- Per-file coverage parsed from output (v8/istanbul table format)
- Delta computed and logged to coverage.md
- Manifest gaps array updated: remove files that hit target, re-sort by coverage
- If coverage command unavailable, skip gracefully (current behavior)

---

## P2 — Intelligence & Safety

### AC-08: Diminishing returns detection
**Priority**: P2 | **Files**: `commands/autocode.md`
**Description**: The orchestrator mentions checking for diminishing returns (Step 9) but doesn't implement it. Track the last 5 coverage deltas. If all 5 are < 0.5%, pause and report. Also track: if last 3 PRs were all rejected by Reviewer, pause.
**Acceptance Criteria**:
- Last 5 coverage deltas tracked (from coverage.md or velocity.md)
- Auto-pause when all 5 deltas < 0.5%
- Auto-pause when last 3 cycles rejected by Reviewer
- Clear message to user: what happened, what to do (re-bootstrap, raise difficulty, manual investigation)
- Can be overridden: user can set `"ignore_diminishing_returns": true` in manifest

### AC-09: Auto-revert on CI failure
**Priority**: P2 | **Files**: `commands/autocode.md`
**Description**: After a PR is merged, monitor CI status. If CI fails on the default branch within 10 minutes of merge, and the failing commit is from AutoCode, create a revert PR automatically.
**Acceptance Criteria**:
- After merge, poll CI status via `gh run list` for up to 10 minutes
- If CI fails, create revert PR: `git revert <commit> && gh pr create`
- Log the regression to failures.md with "CI_REGRESSION" tag
- Downgrade difficulty level by 1
- Revert PR gets the `autocode` label + `revert` label

### AC-10: Cost tracking per cycle
**Priority**: P2 | **Files**: `commands/autocode.md`, `commands/autocode-status.md`
**Description**: Track estimated cost per cycle based on model usage. Log to `.autocode/memory/costs.md`. Display cumulative costs in `/autocode-status`.
**Acceptance Criteria**:
- Per-cycle: count agents spawned, models used, estimated tokens (agent turn count as proxy)
- Cost estimates: haiku ~$0.01/cycle, sonnet ~$0.10/cycle, opus ~$0.50/cycle
- Costs.md updated after each cycle
- Status dashboard shows: total estimated cost, cost per successful PR, cost trend
- Warning when estimated spend exceeds $10 in a session

### AC-11: Manifest auto-refresh
**Priority**: P2 | **Files**: `commands/autocode.md`
**Description**: After every 10 successful cycles, re-run the coverage analysis portion of bootstrap to refresh the gaps list. Files that now have good coverage get removed from gaps. New files that have appeared get added.
**Acceptance Criteria**:
- Every 10 cycles, coverage command re-run
- Gaps list refreshed from actual coverage data
- New files appearing in coverage report added to gaps
- Files at target coverage removed from gaps
- Manifest file updated in-place
- Refresh logged to velocity.md

---

## P3 — Scale & Polish

### AC-12: Parallel pipeline coordination
**Priority**: P3 | **Files**: `commands/autocode.md`
**Description**: Current parallel mode (Step 10) is ad-hoc. Formalize it: maintain a work queue, ensure no two parallel cycles touch the same file or its tests, coordinate memory writes to avoid conflicts.
**Acceptance Criteria**:
- Work queue with file-level locking
- Dependency check: if file A imports file B, they can't run in parallel
- Memory writes batched after all parallel cycles complete
- Failed cycles don't block successful ones
- Max parallel configurable in manifest (default: 3, max: 5)

### AC-13: Bootstrap — cross-language support
**Priority**: P3 | **Files**: `commands/autocode-bootstrap.md`
**Description**: Bootstrap handles TypeScript well (dogfooded). Verify and fix Python (pytest/coverage.py) and Rust (cargo test/tarpaulin) detection. Add Go (go test/go cover) support.
**Acceptance Criteria**:
- Python: detects pytest, installs pytest-cov if missing, parses coverage output
- Rust: detects cargo test, suggests tarpaulin, parses coverage output
- Go: detects go test, parses `go test -cover` output
- Each language has a working example manifest in examples/

### AC-14: Install script improvements
**Priority**: P3 | **Files**: `install.sh`, `uninstall.sh`
**Description**: Make install idempotent (safe to re-run), add version checking, verify symlinks after creation, support both `~/.claude/commands/` and `~/.claude/agents/` paths.
**Acceptance Criteria**:
- Re-running install.sh doesn't create duplicate symlinks
- install.sh prints what it linked and verifies each symlink works
- uninstall.sh only removes autocode symlinks, not other commands
- Both scripts handle missing directories gracefully
- Version check: warn if autocode files are newer than installed symlinks

### AC-15: README launch polish
**Priority**: P3 | **Files**: `README.md`
**Description**: Polish README for public launch. Add: architecture diagram as actual image (not ASCII), badges (license, version), troubleshooting section, FAQ, link to demo video/GIF.
**Acceptance Criteria**:
- Clean architecture diagram (Mermaid or image)
- Badges: MIT license, "works with Claude Code" badge
- Troubleshooting: common issues (no git repo, tests fail, coverage not installed)
- FAQ: cost estimates, supported languages, how to customize
- Dogfood results table updated with latest data

### AC-16: Agent prompt hardening
**Priority**: P3 | **Files**: `agents/*.md`
**Description**: Agent prompts use `{{placeholder}}` syntax but the orchestrator doesn't actually template these. Either implement variable substitution in the orchestrator, or rewrite agent prompts to receive values via the prompt itself.
**Acceptance Criteria**:
- All `{{placeholder}}` references in agent files resolved
- Either: orchestrator does string replacement before spawning agents
- Or: agent prompts rewritten to say "from the manifest you received" instead of `{{variable}}`
- Consistent approach across all 5 agents
- Test with a real cycle to verify agents get the right values

---

## Implementation Order

```
AC-16 (prompt hardening) — unblocks everything else
  ↓
AC-01 (Reviewer gate) + AC-05 (consume failures) — can be parallel
  ↓
AC-04 (rejection loop) — depends on AC-01
  ↓
AC-02 (Architect) + AC-03 (Tester) — can be parallel
  ↓
AC-06 (lessons) + AC-07 (real coverage) — can be parallel
  ↓
AC-08 (diminishing returns) + AC-10 (cost tracking) — can be parallel
  ↓
AC-09 (auto-revert) + AC-11 (manifest refresh)
  ↓
AC-12 through AC-15 — polish phase, any order
```
