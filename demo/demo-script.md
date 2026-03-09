# AutoCode Demo Script

## Setup (before recording)

1. Have a TypeScript project with vitest tests ready (e.g., ghostv2 or any project with a test suite)
2. Install AutoCode: `cd ~/autocode && ./install.sh`
3. Open Claude Code in the target project directory
4. Make sure the project has NO `autocode.manifest.json` yet (delete if exists)
5. Start your terminal recorder (asciinema, VHS, or screen capture)

## Scene 1: Bootstrap (~30 seconds)

```
$ claude
> /autocode-bootstrap
```

Show AutoCode:
- Detecting TypeScript + vitest
- Running tests (all passing)
- Installing coverage tooling
- Generating the manifest
- Displaying coverage gaps

Pause on the manifest output for 3 seconds so viewers can read it.

## Scene 2: First Cycle (~60 seconds)

```
> /autocode
```

Show AutoCode:
- Selecting the first target (lowest coverage file)
- Creating a worktree
- Gathering context (reading the file)
- Builder writing tests
- Tests passing
- Creating the PR

Pause on the cycle summary for 3 seconds.

## Scene 3: Parallel Mode (~45 seconds)

Show AutoCode continuing with 3 parallel cycles:
- "Running 3 cycles in parallel"
- 3 targets selected
- 3 worktrees created
- Results coming in as each completes
- Batch summary

## Scene 4: Status Check (~15 seconds)

```
> /autocode-status
```

Show the dashboard with:
- 4 cycles complete
- Success rate
- Coverage progression
- PRs created

## Scene 5: Report (~15 seconds)

```
> /autocode-report
```

Show the shareable summary being generated.

## Total recording time: ~2.5 minutes

## Post-processing

1. Speed up long waits (agent thinking) to 2-4x
2. Add captions/annotations for key moments
3. Convert to GIF (if using asciinema): `agg demo.cast demo.gif --theme monokai`
4. Or keep as asciinema recording and embed with `<a href="https://asciinema.org/..."><img src="..."/></a>`

## Key moments to highlight

- The manifest generation (shows how AutoCode understands your project)
- The test output (proves tests actually pass)
- The PR creation (proves code ships)
- The parallel mode (shows scale)
- The dashboard (shows accumulated results)
