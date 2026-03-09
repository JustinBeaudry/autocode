# /autocode-next — Dry Run Preview

Preview what the next AutoCode cycle would do, without actually doing it.

## Steps

### Step 0: Verify Prerequisites

1. Check that `autocode.manifest.json` exists. If not: "Run `/autocode-bootstrap` first."
2. Verify `git` is available and this is a git repo
3. Verify `gh` is authenticated: `gh auth status`
4. Check that the test command works: run `manifest.commands.test` and verify it exits successfully
5. If coverage command exists, verify it produces parseable output

Report any issues:
```
Prerequisites:
  ✓ Manifest found
  ✓ Git repo
  ✓ GitHub CLI authenticated
  ✓ Test command works
  ✗ Coverage command failed: <error>
```

### Step 1: Build Work Queue

Run through all work sources (same as the orchestrator's Step 1) but in read-only mode:

#### 1a. Check focus override
Read `.autocode/focus` if it exists. List any focus items.

#### 1b. Check GitHub Issues
```bash
gh issue list --label "autocode" --state open --json number,title,labels --limit 10
```
List any matching issues.

#### 1c. Check coverage gaps
Read the manifest's `coverage.gaps` array. Apply skip rules (parse `failures.md` for failure counts, check cooldowns, check immutable patterns). List eligible gaps.

#### 1d. Check backlog
Read `.autocode/backlog.md` if it exists. List any backlog items.

#### 1e. Check PR review feedback
```bash
gh pr list --label "autocode" --state open --json number,title,reviewDecision
```
List any PRs with pending review feedback.

#### 1f. Check tech debt (if enabled)
If `manifest.work_sources.tech_debt` is enabled, scan for TODO/FIXME comments.

### Step 2: Prioritize and Display

Sort all work items by the prioritization rules (focus > reviews > critical bugs > features/coverage > tech debt).

### Step 3: Display Preview

```
AutoCode Next Cycle Preview
════════════════════════════

Prerequisites: All passed ✓

Work Queue (N items):
  [1] review_response: Address review on PR #42 (src/auth.ts) ← SELECTED
  [2] bugfix: Fix null pointer in payment handler (GH #15)
  [3] coverage: src/utils/parser.ts (15% → target 80%)
  [4] feature: Add webhook retry logic (GH #12)
  [5] coverage: src/services/billing.ts (22% → target 80%)
  ...

Selected Work Item:
  Type:        review_response
  Source:      PR #42 review comments
  Target:      src/auth.ts
  Description: Address 3 review comments on PR #42

Pipeline Configuration:
  Scout:     skip
  Architect: skip
  Builder:   yes (opus)
  Tester:    yes (sonnet)
  Reviewer:  yes (opus)

Context:
  Difficulty:      Level 3
  Previous fails:  0 for this target
  Relevant lessons: 2 found
  Estimated cost:   ~$1.10

No changes made — this is a dry run.
Run /autocode to execute the next cycle.
```

## Notes

- This command is READ-ONLY — no worktrees created, no agents spawned, no memory written
- It helps users understand what AutoCode would do next before committing to a full cycle
- Useful for verifying the work queue after adding focus items or creating GitHub Issues
