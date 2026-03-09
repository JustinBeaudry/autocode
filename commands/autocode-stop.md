# /autocode-stop — Graceful Shutdown

Gracefully stop the AutoCode factory.

## Output Format

Start with the branded header:
```
  ┌─────────────────────────────────────┐
  │  AutoCode — Stop                    │
  │  <repo name> · v4.1                 │
  └─────────────────────────────────────┘
```

## Steps

### 1. Create Stop Signal

Create the `.autocode/STOP` file in the repository root:

```bash
mkdir -p .autocode
echo "Stop requested at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > .autocode/STOP
```

The orchestrator checks for this file between cycles and will stop gracefully after completing its current cycle.

### 2. Check for Active Worktrees

List any active worktrees:

```bash
git worktree list
```

If there are worktrees under `.autocode/worktrees/`, report them. The orchestrator will clean them up on exit, but if the factory crashed, the user may want to clean them manually:

```bash
# To manually clean up orphaned worktrees:
git worktree prune
```

### 3. Report

```
AutoCode stop signal sent.

The factory will stop after completing its current cycle.
If the factory is not running, this signal will prevent the next /autocode from starting until removed.

To resume: delete .autocode/STOP
To clean up orphaned worktrees: git worktree prune
```

### 4. Remove Stop Signal (if asked to resume)

If the user says they want to resume or restart, remove the stop file:

```bash
rm -f .autocode/STOP
```
