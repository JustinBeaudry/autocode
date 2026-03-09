# /autocode-status — Factory Dashboard

Display the current status of the AutoCode factory for this repository.

## Output Format

Start with the branded header:
```
  ┌─────────────────────────────────────┐
  │  AutoCode — Status                  │
  │  <repo name> · Level <N> · v4.1     │
  └─────────────────────────────────────┘
```

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
- `costs.md` — per-cycle cost estimates

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

From the costs log (`.autocode/memory/costs.md`), calculate:
- **Total estimated cost**: Sum of all cycle costs
- **Cost per successful PR**: Total cost / number of successful cycles
- **Cost per coverage point**: Total cost / total coverage delta
- **Cost trend**: Are recent cycles getting cheaper or more expensive?
- **Most expensive cycle**: Which cycle cost the most and why (which agents/models used)

**Cost estimation model** (when actual token counts aren't available):
Estimate per agent spawn based on the model used:
| Model | Estimated cost per agent spawn |
|-------|-------------------------------|
| haiku | ~$0.01 |
| sonnet | ~$0.05-0.15 |
| opus | ~$0.30-1.00 |

Per-cycle estimate = sum of all agent spawns in that cycle.
Typical Level 1-2 cycle (Builder only): ~$0.30-1.00
Typical Level 3+ cycle (Scout + Architect + Builder + Tester + Reviewer): ~$1.50-3.00

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

Cycles:      <total> total (<successes> ✓, <failures> ✗)
Success Rate: <X>%
PRs Created: <N> (<open> open, <merged> merged)

Coverage:    <start>% → <current>% (+<delta>%)
Best Cycle:  +<N>% on <file>
Avg Time:    <N>s per cycle

Budget:
  Session:   $<spent> / $<session_max> (<percent>%)
  Daily:     $<today_spent> / $<daily_budget> (<percent>%)
  Per PR:    ~$<cost_per_pr>
  Per Cov Pt: ~$<cost_per_point>
  Trend:     <cheaper | stable | more expensive> (last 5 cycles)

Top Coverage Gaps Remaining:
  1. <file> — <X>% coverage
  2. <file> — <X>% coverage
  3. <file> — <X>% coverage

Recent Cycles:
  <timestamp> — <file> — ✓/<✗> — <PR URL or reason>
  <timestamp> — <file> — ✓/<✗> — <PR URL or reason>
  <timestamp> — <file> — ✓/<✗> — <PR URL or reason>

Most-Failed:  <file> (<N> attempts)
```

### 6. Cost Warning

If total estimated cost exceeds $10 in the current session, display a warning:
```
⚠️  Estimated spend: $<amount>. Consider pausing to review cost efficiency.
    Run `/autocode-stop` to pause the factory.
```

---

**Expected format of `.autocode/memory/costs.md`**:
```
## Cycle <N> — <timestamp>
- Agents spawned: <list of agent:model pairs>
- Estimated cost: $<amount>
- Cumulative: $<running_total>
```

If any memory files don't exist, show "No data yet — run `/autocode` to start."
