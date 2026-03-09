# /autocode-focus — Priority Work Queue

Manage the focus queue — tell AutoCode what to work on next.

## Output Format

Start with the branded header:
```
  ┌─────────────────────────────────────┐
  │  AutoCode — Focus                   │
  │  <repo name> · v4.1                 │
  └─────────────────────────────────────┘
```

## Usage

```
/autocode-focus <target>       → Queue a file or task for the next cycle
/autocode-focus --list         → Show the current focus queue
/autocode-focus --clear        → Clear the focus queue
```

## Steps

### Adding a Focus Item

1. Parse the argument:
   - If it looks like a file path (contains `/` or `.`): treat as a file target
   - Otherwise: treat as a task description

2. Ensure `.autocode/` directory exists:
   ```bash
   mkdir -p .autocode
   ```

3. Append the item to `.autocode/focus`:
   ```bash
   echo "<item>" >> .autocode/focus
   ```

4. Confirm:
   ```
   Added to focus queue: <item>
   Position: <N> (will be picked up in the next cycle)
   ```

### Listing the Queue (`--list`)

1. Check if `.autocode/focus` exists:
   - If not: "Focus queue is empty. Use `/autocode-focus <target>` to add items."
   - If exists: Read and display each line with its position number

2. Display:
   ```
   Focus Queue:
     1. src/auth.ts
     2. Fix login timeout bug
     3. src/middleware/rate-limit.ts

   These items will be picked up before coverage gaps and other work sources.
   To clear: /autocode-focus --clear
   ```

### Clearing the Queue (`--clear`)

1. Remove the focus file:
   ```bash
   rm -f .autocode/focus
   ```

2. Confirm:
   ```
   Focus queue cleared.
   ```

## How It Works

The orchestrator reads `.autocode/focus` in Step 1a of the work queue. The first line becomes the highest-priority work item. After selecting an item, the orchestrator removes it from the file.

Focus items take priority over all other work sources (GitHub Issues, coverage gaps, backlog, etc.).
