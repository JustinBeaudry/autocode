# /autocode-discover — Proactive Discovery

Find work that needs doing without being told — untested commits, complexity hotspots, vulnerable dependencies, stale TODOs.

## Output Format

Start with the branded header:
```
  ┌─────────────────────────────────────┐
  │  AutoCode — Discover                │
  │  <repo name> · v4.1                 │
  └─────────────────────────────────────┘
```

## Usage

```
/autocode-discover          → Run discovery now and show results
/autocode-discover --dry    → Show what would be discovered without adding to queue
/autocode-discover --clear  → Clear discovered items
```

## Behavior

### Run Discovery

**Trigger**: `/autocode-discover` or `/autocode-discover --dry`

1. **Read manifest**: Load `autocode.manifest.json` and read the `discovery` section. If `discovery` section is missing, use defaults (all modules enabled, 300 line threshold, 30 day TODO age, 5 items per module).

2. **Build existing context** for deduplication:
   - Read current work queue sources (coverage gaps, GitHub Issues, backlog, focus)
   - Read `.autocode/discovery.json` if it exists (previous discoveries)

3. **Spawn Discoverer agent**:
   - `subagent_type`: "general-purpose"
   - `model`: From `manifest.model_routing.scout` (default: "sonnet")
   - `prompt`: Include:
     - Manifest contents
     - Discovery configuration
     - Summary of existing work queue items (file paths and types)
     - Existing discovery items
   - The Discoverer returns a JSON result with discovered items

4. **Display results**:
   ```
   Discovery Results:

   Untested Changes (3 items):
     [coverage] src/handlers/webhook.ts — Commit abc123 by teammate modified without tests
     [coverage] src/services/email.ts — Commit def456 by teammate added 40 lines untested
     [coverage] src/utils/retry.ts — Commit ghi789 by teammate, no test changes

   Complexity Hotspots (2 items):
     [refactor] src/handlers/tools.ts — 450 lines, 23 changes in 30 days
     [refactor] src/db/queries.ts — 380 lines, 15 changes in 30 days

   Dependency Audit (1 item):
     [dependency] express@4.17.1 — CVE-2024-1234 (HIGH severity)

   Stale TODOs (2 items):
     [bugfix] src/cache/redis.ts:42 — FIXME: handle connection timeout (65 days old)
     [feature] src/utils/parser.ts:18 — TODO: support nested objects (45 days old)

   Total: 8 items discovered (2 deduplicated)
   ```

5. **If NOT `--dry`**: Save to `.autocode/discovery.json`:
   ```json
   {
     "discovered_at": "<ISO timestamp>",
     "items": [ ... ]
   }
   ```
   Confirm: "8 items added to discovery queue. These will be picked up by `/autocode` in the next cycle."

6. **If `--dry`**: Do NOT save. Display: "Dry run — no items added. Run without `--dry` to save."

### Clear Discovery

**Trigger**: `/autocode-discover --clear`

1. Delete `.autocode/discovery.json` if it exists
2. Confirm: "Discovery queue cleared."

## Integration with Orchestrator

The orchestrator ingests `discovery.json` as a work source in Step 1 (between backlog and tech debt):
- Items have `source: "discovery"` and default priority 4
- Items from discovery are lower priority than features/bugs but higher than tech debt
- Deduplication prevents the same file from appearing twice in the queue

## When Discovery Runs Automatically

- **Interactive mode**: Once at session start (if `manifest.discovery.enabled` is true), before the first `/autocode` cycle
- **Daemon mode**: Once per daemon run, before the cycle loop starts
- Not every cycle — discovery is expensive and results are stable across cycles

## Error Handling

- If discovery is disabled in manifest: Run anyway (the command is manual — manifest.discovery.enabled controls automatic discovery only)
- If no manifest exists: "Run `/autocode-bootstrap` first."
- If a module fails (e.g., `npm audit` not available): Log warning, skip that module, continue with others
- If no items discovered: "No new work items discovered. Your codebase is looking good!"
