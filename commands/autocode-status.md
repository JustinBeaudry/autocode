# /autocode-status — Factory Dashboard

Display the current status of the AutoCode factory for this repository.

## Steps

### 1. Check Manifest

Read `autocode.manifest.json` from the repo root. If it doesn't exist, tell the user to run `/autocode-bootstrap` first.

### 2. Read Memory Files

Read all memory files from `.autocode/memory/`:
- `velocity.md` — cycle history
- `coverage.md` — coverage progression
- `fixes.md` — successful changes
- `failures.md` — failed attempts
- `lessons.md` — accumulated learnings

### 3. Compute Metrics

From the velocity log, calculate:
- **Total cycles**: Count of all cycles
- **Success rate**: Successes / total cycles
- **Current streak**: Consecutive successes at current level
- **Average cycle time**: Mean duration across all cycles
- **PRs created**: Count of successful cycles
- **Current difficulty level**: From manifest

From the coverage log, calculate:
- **Coverage progression**: Starting coverage → current coverage
- **Total coverage delta**: Sum of all deltas
- **Best single improvement**: Largest delta from one cycle

From the failures log:
- **Most-failed file**: File with the most failure entries
- **Common failure patterns**: Recurring error types

### 4. Check Active State

- Is the factory currently running? Check for `.autocode/STOP` file (absence = might be running)
- Are there active worktrees? Check `.autocode/worktrees/`
- Any open AutoCode PRs? Run `gh pr list --label autocode --state open`

### 5. Display Dashboard

```
AutoCode Status — <repo name>
══════════════════════════════

Factory:     <RUNNING | STOPPED | IDLE>
Level:       <N> — <description>
Streak:      <N> consecutive successes

Cycles:      <total> total (<successes> success, <failures> failed)
Success Rate: <X>%
PRs Created: <N> (<open> open, <merged> merged)

Coverage:    <start>% → <current>% (+<delta>%)
Best Cycle:  +<N>% on <file>
Avg Time:    <N>s per cycle

Top Coverage Gaps Remaining:
  1. <file> — <X>% coverage
  2. <file> — <X>% coverage
  3. <file> — <X>% coverage

Recent Cycles:
  <timestamp> — <file> — <SUCCESS|FAILURE> — <PR URL or reason>
  <timestamp> — <file> — <SUCCESS|FAILURE> — <PR URL or reason>
  <timestamp> — <file> — <SUCCESS|FAILURE> — <PR URL or reason>

Most-Failed:  <file> (<N> attempts)
```

If any memory files don't exist, show "No data yet — run `/autocode` to start."
