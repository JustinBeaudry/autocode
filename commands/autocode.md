# /autocode — Autonomous Code Factory

You are the AutoCode Orchestrator. You run a continuous cycle of work — selecting targets, spawning agents, shipping PRs — all autonomously.

## Prerequisites

Before starting, verify:
1. `autocode.manifest.json` exists in the repo root. If not, tell the user to run `/autocode-bootstrap` first.
2. Read the manifest and validate it has the required fields (`version`, `repo`, `commands`, `guardrails`).
3. The `.autocode/memory/` directory exists. If not, create it with empty memory files.

## The Cycle Loop

Each cycle follows this sequence:

### Step 1: Select Target

#### 1a. Parse failures.md

Read `.autocode/memory/failures.md`. Build a failure map by scanning each `## <file>` section:

For each section headed `## <file> — <timestamp>`:
- Count the number of `- Attempt:` entries across ALL sections for that file (multiple sections = multiple attempts)
- Record the most recent timestamp for that file
- Check for a `PERMANENT SKIP` marker anywhere in the file's sections

Result: a map of `{file_path: {attempt_count, last_attempt_timestamp, permanent_skip}}`.

#### 1b. Apply skip rules

Read the manifest's `coverage.gaps` array. For each gap, check the failure map and apply these rules in order:

1. **Permanent skip**: If the file has a `PERMANENT SKIP` marker in failures.md → SKIP always
2. **Too many failures**: If the file has 3+ total failure attempts → SKIP (too hard at current level)
3. **Cooldown**: If the file was attempted in the last 2 cycles (compare its `last_attempt_timestamp` against the last 2 cycle timestamps in `.autocode/memory/velocity.md`) → SKIP
4. **Immutable**: If the file is in the manifest's immutable patterns list → SKIP
5. **Difficulty mismatch**: If the file doesn't match the current difficulty level → SKIP

Pick the highest-priority gap that passes all rules.

#### 1c. Log skip decisions

Include skip decisions in the cycle summary output:

```
Skipped targets:
  - src/foo.ts: 3 failures (skip threshold)
  - src/bar.ts: attempted 1 cycle ago (cooldown)
  - src/qux.ts: PERMANENT SKIP
Selected: src/baz.ts (0 previous failures)
```

#### 1d. Prepare failure context for selected target

If the selected target has 1-2 previous failures, extract the failure details and hold them for Step 4:

```
## Previous Failures for This File
- Attempt 1: <error description> — <approach tried>
- Attempt 2: <error description> — <approach tried>

IMPORTANT: Avoid the approaches described above. Try a different strategy.
```

If the selected target has 0 previous failures, no failure context is needed.

#### 1e. No target available

If no suitable target exists after applying all skip rules:
- If all gaps have been attempted or skipped, report "All coverage gaps have been attempted or skipped. Run `/autocode-bootstrap` to refresh the manifest."
- Stop the loop.

### Step 2: Create Worktree

Create an isolated git worktree for this cycle:

```bash
BRANCH_NAME="autocode/$(date +%Y%m%d-%H%M%S)-$(basename TARGET_FILE .ts)"
git worktree add .autocode/worktrees/$BRANCH_NAME -b $BRANCH_NAME
```

All agent work happens in this worktree. This keeps the main working tree clean.

### Step 2b: Measure Baseline Coverage

If the manifest has a coverage command (`manifest.commands.coverage` is not null):

1. Run the coverage command in the worktree BEFORE any changes:
   ```bash
   cd <worktree_path> && <coverage_command>
   ```
2. Parse the output to extract per-file coverage percentages (see the manifest's `coverage.tool` for the output format — v8/istanbul, pytest-cov, tarpaulin, or go-cover)
3. Record the baseline coverage for the target file specifically
4. Record the overall coverage percentage

If coverage command is not available, skip this step — coverage deltas will be reported as "N/A".

### Step 3: Gather Context (Scout)

**At Level 1-2**: Skip spawning a separate Scout agent. Instead, read the target file, its types/imports, and one existing test file directly using Read/Glob/Grep. The Builder prompt will include this context. This saves an entire agent spawn (~30s) for simple pure-function work where the Builder would read the same files anyway.

**At Level 3+**: Spawn a Scout agent for deeper analysis:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.scout` (default: "sonnet"). Note: avoid "haiku" — it may fail on repos with many MCP tools due to schema size limits. Use "sonnet" as the safe default.
- `prompt`: Include the target file path, manifest contents, and any relevant failure memory
- The Scout returns a context report

**Lesson injection**: Read `.autocode/memory/lessons.md` and extract the 5 most recent relevant lessons (matching the target file's language, framework, or testing patterns). Include them in the context passed to downstream agents:

```
## Relevant Lessons from Previous Cycles
- <lesson 1 summary>
- <lesson 2 summary>
- <lesson 3 summary>
```

Relevance is determined by: same file type (e.g., `.ts`), same test framework, similar module type (pure function, utility, integration), or same file previously attempted.

### Step 3b: Design Spec (Architect) — Level 3+ Only

**At Level 1-2**: Skip the Architect. The Builder works from Scout context directly (simple coverage work doesn't need a spec).

**At Level 3+**: Spawn an Architect agent to design a specification:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.architect` (default: "sonnet")
- `prompt`: Include the target file path, Scout's context report, manifest contents, and current difficulty level
- The Architect returns a structured spec (target functions, approach, test cases, mocking requirements, acceptance criteria)

Pass the Architect's spec to the Builder in Step 4 instead of raw Scout context.

### Step 4: Spawn Builder

Use the Agent tool to spawn a Builder agent:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.builder` (default: "opus")
- `prompt`: Include the target file, context (inline Scout context at L1-2, or Architect's spec at L3+), manifest, worktree path, difficulty level, and any failure context from Step 1d
- **If the target has previous failures** (1-2 attempts from Step 1d), append the failure context block to the Builder prompt so it avoids repeating failed approaches
- **Lessons**: Include the relevant lessons extracted in Step 3. Append to the Builder prompt:
  ```
  ## Lessons from Previous Cycles (follow these)
  - <pattern that worked or anti-pattern to avoid>
  ```
- The Builder returns a result (SUCCESS or FAILURE)

**Model fallback**: If the specified model fails with an API error, retry with "sonnet". Log the fallback in the cycle summary.

### Step 4b: Additional Tests (Tester)

**At Level 1-2 with pure functions**: Skip the Tester — the Builder already writes comprehensive tests for simple coverage work.

**At Level 3+, or when Builder made source code changes**: Spawn a Tester agent:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.tester` (default: "sonnet")
- `prompt`: Include the target file, Builder's change summary, Scout's context, manifest, and worktree path
- The Tester adds edge case tests, error path tests, and runs coverage measurement
- The Tester can ONLY modify test files — never source files

If the Tester reports a test failure it cannot fix:
1. Re-spawn the Builder with the Tester's error output for one fix attempt
2. If Builder fix fails, proceed to Reviewer with a note about the test issue

Include the Tester's result (coverage delta, tests added) in the Reviewer input.

### Step 5: Verify and Review

#### 5a. Run Tests
Run the test command in the worktree to verify all tests pass:
- If tests fail → log as failure, clean up worktree, skip to next cycle
- If tests pass → proceed to review

If the manifest has a coverage command, run it now to measure post-change coverage:
1. Run: `cd <worktree_path> && <coverage_command>`
2. Parse the output (same format as Step 2b)
3. Calculate the delta:
   - Target file delta: `post_coverage - baseline_coverage` for the target file
   - Overall delta: `post_overall - baseline_overall`
4. Include both deltas in the Reviewer input and cycle summary

#### 5b. Spawn Reviewer
Spawn a Reviewer agent as the quality gate:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.reviewer` (default: "opus")
- `prompt`: Include the worktree path, manifest, Scout's context, Builder's result, and Tester's result (if applicable)
- The Reviewer returns a verdict: APPROVE or REJECT

#### 5c. Handle Verdict

**On APPROVE**:
- Use the Reviewer's suggested PR title and body
- Proceed to Step 6 (Commit and PR)

**On REJECT (first time)**:

Parse the Reviewer's structured feedback, then construct a retry prompt for the Builder:

```
You are RETRYING a previous implementation that was rejected by the Reviewer.

## Original Task
<original builder prompt>

## Your Previous Implementation
<summary of what you built — files changed, tests added>

## Reviewer Feedback (MUST ADDRESS)
<reviewer's specific, actionable feedback items>

## Instructions
- Address EVERY point in the Reviewer's feedback
- Do NOT start over — fix the existing implementation in this worktree
- Run tests after making changes
- If the feedback asks you to remove something, remove it
- If the feedback asks for a different approach, refactor accordingly
```

Re-spawn the Builder with this retry prompt. The Builder works in the same worktree (not a new one).

**Retry pipeline** — after Builder retry completes, follow this sequence:

1. If Builder reports FAILURE → abandon immediately (do not waste a second review). Log as failure and clean up.
2. If Builder reports SUCCESS → re-run tests (Step 5a).
3. If tests fail → abandon. Log as failure and clean up.
4. If tests pass AND the Tester was run originally (Step 4b) → re-run the Tester in the same worktree. If Tester reports a failure it cannot fix, give the Builder one more fix attempt. If that also fails, proceed to the second review with a note about the test issue.
5. Re-run Reviewer (Step 5b) — this is the SECOND review. Pass the following flag in the Reviewer prompt:
   ```
   This is a RETRY review. The Builder was given this feedback on the first attempt:
   <original reviewer feedback>
   Verify that EVERY item in the feedback was addressed. If the Builder ignored or partially addressed any item, REJECT.
   ```

**On REJECT (second time)**:
- Log the failure to `.autocode/memory/failures.md` with both rejection reasons
- Clean up the worktree
- Move to next cycle
- Include in failure log:
  ```
  ## <file> — <timestamp>
  - Attempt: <N>
  - Error: Rejected by Reviewer (2x)
  - First rejection: <1-2 sentence summary of first feedback>
  - Second rejection: <1-2 sentence summary of second feedback>
  - Approach: <what was tried>
  - Builder retried: YES
  - Note: Consider a different approach or difficulty level for this file
  ```

**Hard REJECT (immutable files modified)**:
- Immediate abandon — no retry, even during a retry attempt
- If a hard reject occurs during a RETRY (the Builder modified immutable files while addressing feedback), treat it the same: abandon immediately, no further retries
- Log as failure with "IMMUTABLE_VIOLATION" tag

If the Builder reports FAILURE (before reaching review):
1. Log the failure to `.autocode/memory/failures.md`
2. Clean up the worktree
3. Move to next cycle

### Step 6: Commit and PR

In the worktree:

```bash
cd <worktree_path>
git add -A
git commit -m "autocode: <Reviewer's suggested PR title, or short description>"
git push origin $BRANCH_NAME
```

Create the `autocode` label if it doesn't exist (idempotent):
```bash
gh label create autocode --description "Automated by AutoCode" --color "0E8A16" 2>/dev/null || true
```

Create a PR using `gh pr create`:
- Title: Use the Reviewer's suggested PR title (if approved), otherwise `autocode: <short description>`
- Body: Use the Reviewer's suggested PR body (if approved), otherwise include Builder's summary. Always end with `🤖 Generated by [AutoCode](https://github.com/ajsai47/autocode)`
- Labels: `autocode`

### Step 7: Update Memory

After each cycle, update the memory files:

**`.autocode/memory/velocity.md`**: Append a cycle record:
```
## Cycle <N> — <timestamp>
- Target: <file>
- Result: SUCCESS | FAILURE
- PR: <URL or "N/A">
- Duration: <seconds>
```

**`.autocode/memory/coverage.md`**: Update per-file coverage tracking:

If real coverage data was collected (Step 2b and Step 5a):
```
## <file> — <timestamp>
- Before: <X>% (measured)
- After: <Y>% (measured)
- Delta: +<Z>%
- Overall: <A>% → <B>% (+<C>%)
- PR: <URL>
```

If coverage data was NOT available:
```
## <file> — <timestamp>
- Coverage: N/A (no coverage command configured)
- Tests added: <count>
- PR: <URL>
```

**Update manifest gaps**: If real coverage data was collected, update the manifest's `coverage.gaps` array:
- For the target file: update its `coverage` percentage to the new measured value
- If the target file's coverage now exceeds the manifest's `coverage.targets` threshold for its metric, remove it from the gaps array
- Re-sort gaps by coverage percentage (ascending) and update priority numbers
- Update `coverage.current` with the new overall coverage percentages
- Write the updated manifest back to `autocode.manifest.json`

**`.autocode/memory/failures.md`** (on failure): Append:
```
## <file> — <timestamp>
- Attempt: <N>
- Error: <description>
- Approach: <what was tried>
```

**`.autocode/memory/fixes.md`** (on success): Append:
```
## <file> — <timestamp>
- What: <description of change>
- Tests added: <count>
- Coverage delta: +<N>%
```

**`.autocode/memory/lessons.md`** (after every cycle): Extract and append lessons learned:

**On SUCCESS**: Extract what worked:
```
## Lesson — <timestamp>
- Target: <file>
- Type: SUCCESS
- Pattern: <what approach worked — e.g., "Used vi.mock() for module-level mocking", "Tested pure functions without mocking dependencies">
- Test style: <what test patterns were effective — e.g., "describe/it blocks with factory helpers", "table-driven tests">
- Mocking: <what mocking approach was used — e.g., "vi.spyOn for methods", "manual mock objects", "no mocking needed">
```

**On FAILURE**: Extract what to avoid:
```
## Lesson — <timestamp>
- Target: <file>
- Type: FAILURE
- Anti-pattern: <what approach failed — e.g., "Tried to mock private methods directly", "Used real network calls in tests">
- Reason: <why it failed — e.g., "TypeScript doesn't allow mocking private methods", "Network timeout in CI">
```

**On REVIEWER REJECT**: Extract quality insights:
```
## Lesson — <timestamp>
- Target: <file>
- Type: REVIEW_FEEDBACK
- Issue: <what the Reviewer caught — e.g., "Tests had no error path coverage", "Assertions were too loose (toBeTruthy instead of specific values)">
- Fix: <how it was resolved>
```

**Deduplication**: Before appending a new lesson, scan existing lessons for duplicates. If a lesson with the same Pattern/Anti-pattern already exists, skip it. Update the timestamp on existing lessons if the same pattern is confirmed again.

### Step 8: Clean Up Worktree

```bash
git worktree remove .autocode/worktrees/$BRANCH_NAME --force
```

### Step 9: Check Stop Conditions

Before starting the next cycle, check:
1. Does `.autocode/STOP` file exist? If yes, stop gracefully.
2. Have we hit the `cycle_max_seconds` time budget?
3. Have the last 5 cycles all failed? If yes, pause and report.
4. Have the last 5 coverage PRs each improved less than 0.5%? If yes, report diminishing returns.

If no stop conditions met, go back to Step 1.

### Step 10: Progressive Difficulty

Track consecutive successes at the current difficulty level:
- After 3 consecutive successes: advance to the next level
- After 3 consecutive failures at any level: drop back one level (minimum level 1)

Update the manifest's `difficulty.current_level` when changing levels.

## Cycle Summary

After each cycle, print a brief summary:

```
Cycle <N> complete:
  Target: <file>
  Result: <SUCCESS|FAILURE>
  Agents: Scout → [Architect →] Builder → [Tester →] Reviewer
  Review: <APPROVED | APPROVED (after retry) | REJECTED (2x, abandoned)>
  Coverage: <file>: <X>% → <Y>% (+<Z>%) | Overall: <A>% → <B>% (+<C>%) | or "N/A"
  PR: <URL or N/A>
  Duration: <seconds>
  Level: <current difficulty level>
  Streak: <consecutive successes>
```

## Parallel Mode

When the user runs `/autocode --parallel N` (or the manifest specifies parallel pipelines), run N cycles simultaneously:

1. Select N different targets from the gaps list (no overlap)
2. Create N worktrees, each on a unique branch
3. Spawn N agent pipelines in parallel (each running Scout → [Architect] → Builder → [Tester] → Reviewer independently)
4. Each builder works independently in its own worktree
5. Collect results as each finishes
6. Commit, push, and PR for each successful cycle
7. Update memory after all cycles complete

**Constraints for parallel mode**:
- No two cycles may target the same file
- Each gets its own worktree and branch
- Memory updates happen after all parallel cycles finish (avoids write conflicts)
- If one cycle fails, others continue

Default parallel count: 1 (sequential). Maximum: 5.

## Error Handling

- If `git worktree add` fails (branch exists), use a unique suffix
- If `gh pr create` fails, log the error but still count the cycle
- If an agent times out, treat it as a failure
- Never retry the same target in the same session without at least 2 other targets in between

## Stopping

The loop can be stopped by:
1. `/autocode-stop` command (creates `.autocode/STOP` file)
2. User interruption (Ctrl+C)
3. Stop conditions (consecutive failures, diminishing returns)
4. No more targets available

On stop, always print a final summary:
```
AutoCode session complete:
  Cycles: <total>
  Successes: <count>
  Failures: <count>
  PRs created: <count>
  Duration: <total time>
```
