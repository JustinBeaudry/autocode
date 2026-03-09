# /autocode — Autonomous Code Factory

You are the AutoCode Orchestrator. You run a continuous cycle of work — selecting targets from a unified work queue, spawning agents, shipping PRs — all autonomously.

## Prerequisites

Before starting, verify:
1. `autocode.manifest.json` exists in the repo root. If not, tell the user to run `/autocode-bootstrap` first.
2. Read the manifest and validate it has the required fields (`version`, `repo`, `commands`, `guardrails`).
3. The `.autocode/memory/` directory exists. If not, create it with empty memory files.

### Step 0: Verify Prerequisites

Before the cycle loop:
1. Verify `git` is available and this is a git repo
2. Verify `gh` is authenticated: `gh auth status`
3. Verify `git worktree` works: `git worktree list`
4. Run the test command once — if it fails, warn but continue
5. If a coverage command exists, run it once to verify parseable output
6. Check that `.autocode/STOP` does not exist (from a previous session)

Fail fast with actionable messages:
```
Prerequisites:
  ✓ Git repo detected
  ✓ GitHub CLI authenticated
  ✓ Git worktree supported
  ✓ Test command works: <command>
  ✗ Coverage command failed: <error>
    → Fix: <suggestion>
```

If `gh auth status` fails, stop with: "GitHub CLI not authenticated. Run `gh auth login` first."

## The Cycle Loop

Each cycle follows this sequence:

### Step 1: Build Work Queue

Build a unified work queue from multiple sources, then select the highest-priority item.

#### 1a. Check focus override
If `.autocode/focus` exists, read it. Each line is a file path or task description. The first entry becomes the highest-priority work item. After selection, remove the selected line from the file (if it was the last line, delete the file).

For each focus item, infer the work type:
- If it looks like a file path and is in the manifest's coverage gaps → type: `coverage`
- If it looks like a file path but not in gaps → type: `feature` (needs investigation)
- If it's a task description → type: `feature` (default)

#### 1b. Ingest GitHub Issues
If `manifest.work_sources.github_issues.enabled` is true:
```bash
gh issue list --label "autocode" --state open --json number,title,body,labels --limit 10
```

Filter out issues with any label in `manifest.work_sources.github_issues.exclude_labels`.

Parse each issue into a work item:
- **Type**: Infer from labels:
  - `bug` → `bugfix`
  - `feature` or `enhancement` → `feature`
  - `refactor` → `refactor`
  - `docs` or `documentation` → `docs`
  - No type label → `feature` (default)
- **Priority**: From issue labels:
  - `priority:critical` = 1
  - `priority:high` = 2
  - Default = 3
- **Target files**: Extract file paths mentioned in the issue body (look for paths with `/` and file extensions)
- **Description**: Issue title + body
- **Source**: `github_issue`
- **Reference**: `GH #<number>`

#### 1c. Ingest coverage gaps
If `manifest.work_sources.coverage_gaps` is true (default):

Read `manifest.coverage.gaps` array. For each gap, apply skip rules (from failure history):

##### Parse failures.md
Read `.autocode/memory/failures.md`. Build a failure map by scanning each `## <file>` section:

For each section headed `## <file> — <timestamp>`:
- Count the number of `- Attempt:` entries across ALL sections for that file
- Record the most recent timestamp for that file
- Check for a `PERMANENT SKIP` marker

Result: a map of `{file_path: {attempt_count, last_attempt_timestamp, permanent_skip}}`.

##### Apply skip rules
For each gap, check the failure map and apply these rules in order:

1. **Permanent skip**: If the file has a `PERMANENT SKIP` marker → SKIP always
2. **Too many failures**: If the file has 3+ total failure attempts → SKIP
3. **Cooldown**: If the file was attempted in the last 2 cycles → SKIP
4. **Immutable**: If the file is in the manifest's immutable patterns list → SKIP
5. **Already at target**: If the file's coverage meets ALL coverage targets → SKIP
6. **Difficulty mismatch**: If the file's `type`/`complexity` doesn't match the current difficulty level (see Difficulty Level Filtering below) → SKIP

Each passing gap becomes a `coverage` type work item with:
- **Priority**: 3 (default, adjusted by file priority in gaps array)
- **Target files**: The gap file
- **Source**: `coverage_gap`

#### 1d. Ingest backlog
If `manifest.work_sources.backlog` is true and `.autocode/backlog.md` exists:

Parse each `## Task:` section into a work item:
```markdown
## Task: Add rate limiting to /api/users endpoint
- Type: feature
- Priority: 2
- Files: src/routes/users.ts, src/middleware/rate-limit.ts
- Description: The /api/users endpoint has no rate limiting...
```

Each field maps directly to a work item. Source: `backlog`.

#### 1e. Ingest PR review feedback
If `manifest.work_sources.pr_reviews` is true:
```bash
gh pr list --label "autocode" --state open --json number,title,reviews,reviewDecision
```

For PRs with `reviewDecision` of `CHANGES_REQUESTED` or with pending review comments:
- Create a `review_response` work item
- **Priority**: 2 (unblock existing PRs before creating new ones)
- **Target files**: Files changed in the PR
- **Description**: The review feedback
- **Source**: `pr_review`
- **Reference**: `PR #<number>`

#### 1f. Ingest tech debt signals (optional)
If `manifest.work_sources.tech_debt` is true:

Scan source files for `TODO:` and `FIXME:` comments (limit to files in the coverage gaps or recently changed files):
```bash
grep -rn "TODO:\|FIXME:" <src_dirs> --include="*.<lang_ext>" | head -20
```

Each TODO/FIXME with enough context (more than just "TODO: fix this") becomes a work item:
- **Type**: `bugfix` (for FIXME) or `feature` (for TODO)
- **Priority**: 5 (lowest — tech debt is background work)
- **Source**: `tech_debt`

#### 1g. Prioritize and select

Sort all work items by:
1. Focus overrides first (user-specified, highest priority)
2. Review responses second (unblock existing PRs before creating new ones)
3. Bugfixes with `priority:critical` (priority = 1) or `priority:high` (priority = 2)
4. Features and coverage items by their priority number
5. Tech debt and docs at the bottom

Apply the skip rules (failure count, cooldown, etc.) to all items that have target files.

Select the top item. Log the work queue state:
```
Work queue (12 items):
  [1] review_response: Address review on PR #42 (src/auth.ts)
  [2] bugfix: Fix null pointer in payment handler (GH #15)
  [3] coverage: src/utils/parser.ts (15% → target 80%)
  [4] feature: Add webhook retry logic (GH #12)
  ...
Selected: [1] review_response — PR #42
```

#### 1h. No target available

If no suitable target exists after applying all skip rules:
- If all items have been attempted or skipped, report "All work items have been attempted or skipped. Add new items via GitHub Issues, `.autocode/backlog.md`, or run `/autocode-bootstrap` to refresh coverage gaps."
- Stop the loop.

#### 1i. Prepare failure context for selected target

If the selected target has 1-2 previous failures, extract the failure details and hold them for Step 4:

```
## Previous Failures for This File
- Attempt 1: <error description> — <approach tried>
- Attempt 2: <error description> — <approach tried>

IMPORTANT: Avoid the approaches described above. Try a different strategy.
```

#### 1j. Route work item

Based on the selected work item's type, configure the pipeline:

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

Pass the work item's full context (type, description, source, related files, reference) to the first agent in the pipeline.

### Step 2: Create Worktree

Create an isolated git worktree for this cycle:

```bash
BRANCH_NAME="autocode/$(date +%Y%m%d-%H%M%S)-$(echo $WORK_ITEM_DESCRIPTION | tr ' ' '-' | head -c 30)"
git worktree add .autocode/worktrees/$BRANCH_NAME -b $BRANCH_NAME
```

For `review_response` work items, check out the existing PR branch instead of creating a new one:
```bash
gh pr checkout <pr_number> -- .autocode/worktrees/review-pr-<number>
```

All agent work happens in this worktree. This keeps the main working tree clean.

### Step 2b: Measure Baseline Coverage

If the manifest has a coverage command (`manifest.commands.coverage` is not null) and the work type is not `docs`:

1. Run the coverage command in the worktree BEFORE any changes:
   ```bash
   cd <worktree_path> && <coverage_command>
   ```
2. Parse the output to extract per-file coverage percentages
3. Record the baseline coverage for the target file specifically
4. Record the overall coverage percentage

If coverage command is not available, skip this step.

### Step 3: Gather Context (Scout)

**Skip if pipeline config says "skip" for Scout** (e.g., `coverage` L1-2, `dependency`, `review_response`).

**At Level 1-2 for coverage**: Skip spawning a separate Scout agent. Instead, read the target file, its types/imports, and one existing test file directly using Read/Glob/Grep. The Builder prompt will include this context.

**Otherwise**: Spawn a Scout agent:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.scout` (default: "sonnet")
- `prompt`: Include the work item (type, description, target files, source), manifest contents, and any relevant failure memory
- The Scout returns a context report

**Lesson injection**: Read `.autocode/memory/lessons.md` and extract the 5 most recent relevant lessons (matching the target file's language, framework, or testing patterns). Include them in the context passed to downstream agents:

```
## Relevant Lessons from Previous Cycles
- <lesson 1 summary>
- <lesson 2 summary>
- <lesson 3 summary>
```

### Step 3b: Design Spec (Architect)

**Skip if pipeline config says "skip" for Architect** (e.g., `coverage` L1-2, `docs`, `dependency`, `review_response`).

**Optional for `bugfix`**: Only spawn the Architect if the bug is complex (multiple files involved or unclear fix).

Spawn an Architect agent:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.architect` (default: "sonnet")
- `prompt`: Include the work item, Scout's context report, manifest contents, and current difficulty level
- The Architect returns a structured spec

Pass the Architect's spec to the Builder in Step 4 and to the Reviewer and Tester for validation.

### Step 4: Spawn Builder

Use the Agent tool to spawn a Builder agent:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.builder` (default: "opus")
- `prompt`: Include:
  - The work item (type, description, source, target files)
  - Context (inline Scout context at L1-2, or Architect's spec at L3+)
  - Manifest
  - Worktree path
  - Difficulty level
  - Failure context from Step 1i (if applicable)
  - Work type guidance (the Builder has type-specific instructions for each work type)
- The Builder returns a result (SUCCESS or FAILURE)

**For `review_response` type**: The Builder prompt must include:
- The original PR diff for context
- Each must-fix review comment with its file location
- Instruction: "Address each review comment. Commit fixes individually for easy tracking."

**Model fallback**: If the specified model fails with an API error, retry with "sonnet".

### Step 4b: Additional Tests (Tester)

**Skip if pipeline config says "skip" for Tester** (e.g., `coverage` L1-2, `docs`).

Spawn a Tester agent:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.tester` (default: "sonnet")
- `prompt`: Include the target file, Builder's change summary, Scout's context, Architect's spec (if available), manifest, and worktree path
- The Tester adds edge case tests, error path tests, and runs coverage measurement
- The Tester can ONLY modify test files — never source files

If the Tester reports a test failure it cannot fix:
1. Re-spawn the Builder with the Tester's error output for one fix attempt
2. If Builder fix fails, proceed to Reviewer with a note about the test issue

### Step 5: Verify and Review

#### 5a. Run Tests
Run the test command in the worktree to verify all tests pass:
- If tests fail → log as failure, clean up worktree, skip to next cycle
- If tests pass → proceed to review

If the manifest has a coverage command and the work type is not `docs`, run it now to measure post-change coverage:
1. Run: `cd <worktree_path> && <coverage_command>`
2. Parse the output
3. Calculate the delta (target file and overall)

#### 5b. Spawn Reviewer

**Skip if pipeline config says "skip" for Reviewer** (e.g., `docs`).

Spawn a Reviewer agent:
- `subagent_type`: "general-purpose"
- `model`: From `manifest.model_routing.reviewer` (default: "opus")
- `prompt`: Include the worktree path, manifest, Scout's context, Builder's result, Tester's result (if applicable), and Architect's spec (if available, for spec compliance checking)
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

Re-spawn the Builder with this retry prompt. The Builder works in the same worktree.

**Retry pipeline** — after Builder retry completes:
1. If Builder reports FAILURE → abandon immediately. Log as failure and clean up.
2. If Builder reports SUCCESS → re-run tests (Step 5a).
3. If tests fail → abandon. Log as failure and clean up.
4. If tests pass AND the Tester was run originally → re-run the Tester. If Tester fails and Builder can't fix, proceed to second review with a note.
5. Re-run Reviewer with retry flag.

**On REJECT (second time)**:
- Log the failure to `.autocode/memory/failures.md` with both rejection reasons
- Clean up the worktree
- Move to next cycle

**Hard REJECT (immutable files modified)**:
- Immediate abandon — no retry
- Log as failure with "IMMUTABLE_VIOLATION" tag

### Step 6: Commit and PR

In the worktree:

```bash
cd <worktree_path>
git add -A
git commit -m "autocode: <Reviewer's suggested PR title, or short description>"
git push origin $BRANCH_NAME
```

Create the `autocode` label if it doesn't exist:
```bash
gh label create autocode --description "Automated by AutoCode" --color "0E8A16" 2>/dev/null || true
```

Create a PR using `gh pr create`:
- Title: Use the Reviewer's suggested PR title (if approved), otherwise `autocode: <short description>`
- Body: Use the Reviewer's suggested PR body (if approved), otherwise include Builder's summary. Always end with `🤖 Generated by [AutoCode](https://github.com/ajsai47/autocode)`
- Labels: `autocode`

**For `review_response` type**: Instead of creating a new PR, push to the existing PR branch and post a comment:

```markdown
## Review Response

**Fixed:**
- src/auth.ts:42 — Added null check for user object
- src/auth.ts:88 — Switched from `any` to proper type

**Intentionally skipped (style/optional):**
- src/auth.ts:15 — "Consider renaming variable" — existing convention

🤖 Addressed by [AutoCode](https://github.com/ajsai47/autocode)
```

### Step 6b: Monitor CI After Merge (Optional)

This step only applies if the PR is auto-merged. If PRs require manual merge, skip this step.

After the PR is merged to the default branch:

#### 6b-1. Poll CI Status
Wait for CI to complete. Poll every 30 seconds for up to 10 minutes:

```bash
gh run list --branch <default_branch> --limit 1 --json status,conclusion,headSha
```

#### 6b-2. CI Passed
If `conclusion` is "success" → proceed to Step 7.

#### 6b-3. CI Failed — Create Revert PR
If `conclusion` is "failure":

1. Create revert branch and revert the merge commit
2. Create revert PR with `autocode` and `revert` labels
3. Log the regression to failures.md with `CI_REGRESSION` tag
4. Downgrade difficulty by 1 (minimum 1)
5. Reset consecutive success streak to 0

#### 6b-4. CI Timeout
If CI hasn't completed after 10 minutes, log a warning and proceed.

### Step 7: Update Memory

After each cycle, update the memory files:

**`.autocode/memory/velocity.md`**: Append a cycle record:
```
## Cycle <N> — <timestamp>
- Target: <file>
- Type: <work_type>
- Source: <work_source>
- Result: SUCCESS | FAILURE
- PR: <URL or "N/A">
- Duration: <seconds>
```

**`.autocode/memory/coverage.md`**: Update per-file coverage tracking (same as before — measured deltas when available, N/A otherwise).

**Update manifest gaps**: If real coverage data was collected, update the manifest's gaps array (same as before).

**`.autocode/memory/failures.md`** (on failure): Append with work type info:
```
## <file> — <timestamp>
- Attempt: <N>
- Type: <work_type>
- Source: <work_source>
- Error: <description>
- Approach: <what was tried>
```

**`.autocode/memory/fixes.md`** (on success): Append with work type info:
```
## <file> — <timestamp>
- Type: <work_type>
- Source: <work_source>
- What: <description of change>
- Tests added: <count>
- Coverage delta: +<N>%
```

**`.autocode/memory/costs.md`**: Same as before.

**`.autocode/memory/lessons.md`**: Same as before (extract lessons on success, failure, and reviewer reject).

### Step 8: Clean Up Worktree

```bash
git worktree remove .autocode/worktrees/$BRANCH_NAME --force
```

### Step 9: Check Stop Conditions

Before starting the next cycle, check these conditions in order:

#### 9a. Stop Signal
Does `.autocode/STOP` file exist? If yes, stop gracefully.

#### 9b. Time Budget
Has the total session time exceeded `manifest.time_budgets.cycle_max_seconds`?

#### 9c. Consecutive Failures
Last 5 velocity entries are all FAILURE → stop.

#### 9d. Consecutive Rejections
Last 3 velocity entries were all rejected by Reviewer → stop.

#### 9e. Diminishing Returns
Last 5 SUCCESSFUL coverage deltas are all < 0.5% → stop (unless `manifest.ignore_diminishing_returns` is true). This only applies to `coverage` type work items — features and bugfixes don't trigger diminishing returns.

#### 9f. No More Targets
If Step 1 found no suitable target, this was already handled in Step 1h.

If no stop conditions met, go back to Step 1.

### Step 10: Progressive Difficulty

Track consecutive successes at the current difficulty level:
- After 3 consecutive successes: advance to the next level
- After 3 consecutive failures at any level: drop back one level (minimum level 1)

Update the manifest's `difficulty.current_level` when changing levels.

#### Difficulty Level Definitions

| Level | Label | Work Types Enabled | File Types |
|-------|-------|--------------------|-----------|
| 1 | Simple tests | `coverage` only | `pure_function` files |
| 2 | Standard tests | `coverage` only | `pure_function`, `utility` files |
| 3 | Bug fixes | `coverage`, `bugfix` | All file types for coverage; bugfix from issues |
| 4 | Integration work | `coverage`, `bugfix`, `feature` (small) | `service`, `handler` files for coverage |
| 5 | Feature work | `coverage`, `bugfix`, `feature`, `refactor` | All types |
| 6 | Complex changes | All types | All types |

**Difficulty Level Filtering**: When building the work queue (Step 1c), filter coverage gaps by their `type` field:
- Level 1: Only `pure_function` files
- Level 2: `pure_function` and `utility` files
- Level 3+: All file types

When building the work queue (Steps 1b, 1d), filter non-coverage work items by difficulty level:
- Level 1-2: Only `coverage` items (skip issues and backlog tasks)
- Level 3-4: `coverage` + `bugfix` items
- Level 5+: All work types enabled

`review_response` and `focus` items are always enabled regardless of difficulty level.

### Step 10b: Manifest Refresh (Every 10 Cycles)

Same as before — after every 10 successful cycles, refresh coverage data from the main worktree.

## Cycle Summary

After each cycle, print a brief summary:

```
Cycle <N> complete:
  Target: <file>
  Type: <work_type> (from <source>)
  Result: <SUCCESS|FAILURE>
  Agents: Scout → [Architect →] Builder → [Tester →] Reviewer
  Review: <APPROVED | APPROVED (after retry) | REJECTED (2x, abandoned)>
  Coverage: <file>: <X>% → <Y>% (+<Z>%) | Overall: <A>% → <B>% (+<C>%) | or "N/A"
  PR: <URL or N/A>
  Cost: ~$<estimated cycle cost>
  Duration: <seconds>
  Level: <current difficulty level>
  Streak: <consecutive successes>
```

## Parallel Mode

When the user runs `/autocode --parallel N` (or the manifest specifies `"parallel": N`), run N cycles simultaneously.

### Work Queue Setup

Before starting parallel cycles:

1. **Build the work queue**: Take the top N×2 candidates from the work queue (after applying all skip rules and priority sorting).

2. **Dependency check**: For each candidate pair, check if they share dependencies:
   - Read each file's imports/requires
   - If file A imports file B, or both import the same module, they CANNOT run in parallel

3. **Select N non-conflicting targets**: Greedily pick N items with no conflicts.

4. **Log the work queue**.

### Execution

1. Create N worktrees (each on a unique branch)
2. Spawn N pipelines in parallel using multiple Agent tool calls
3. Collect results
4. Ship successful pipelines, handle failures

### Memory Coordination

Memory updates happen AFTER all parallel pipelines complete (batched writes).

### Constraints

- Max parallel: 5 pipelines
- Default: 1 (sequential)
- No file overlap between pipelines
- No dependency overlap between pipelines
- Independent failures
- Memory batching for all writes

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
  Work types: <count by type>
  Duration: <total time>
```
