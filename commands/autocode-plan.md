# /autocode-plan — Multi-PR Planning

Decompose large tasks into a dependency graph of atomic PRs.

## Output Format

Start with the branded header:
```
  ┌─────────────────────────────────────┐
  │  AutoCode — Plan                    │
  │  <repo name> · v4.1                 │
  └─────────────────────────────────────┘
```

## Usage

```
/autocode-plan <description or issue URL>  → Decompose into a multi-PR plan
/autocode-plan --list                      → Show all active plans
/autocode-plan --show <plan-id>            → Show plan details with progress
/autocode-plan --cancel <plan-id>          → Cancel a plan
```

## Behavior

### Create a Plan

**Trigger**: `/autocode-plan <description or issue URL>`

1. **Parse input**:
   - If the argument looks like a GitHub Issue URL or `#<number>`, fetch the issue body:
     ```bash
     gh issue view <number> --json title,body,labels
     ```
   - Otherwise, treat the argument as a task description

2. **Read manifest**: Load `autocode.manifest.json` and verify `manifest.planning.enabled` is true. If not, tell the user: "Multi-PR planning is disabled. Set `planning.enabled: true` in your manifest."

3. **Read context**:
   - Load `.autocode/memory/knowledge.json` (knowledge graph)
   - Load `.autocode/memory/patterns.json` (pattern database, top 10 patterns)

4. **Spawn Planner agent**:
   - `subagent_type`: "general-purpose"
   - `model`: From `manifest.model_routing.architect` (default: "sonnet")
   - `prompt`: Include:
     - The task description (or issue body)
     - Manifest contents
     - Knowledge graph contents
     - Top 10 patterns from pattern database
   - The Planner returns a structured plan JSON

5. **Present for review**: Display the plan to the user:
   ```
   Plan: <title>
   Source: <source> (<reference>)
   Steps: <count>

   Dependency Graph:
     step_1: <title> [no dependencies]
     step_2: <title> [blocked by: step_1]
     step_3: <title> [blocked by: step_1]
     step_4: <title> [blocked by: step_2, step_3]

   Estimated PRs: <count>
   Target files: <unique file count>
   ```

6. **On approval**:
   - Create `.autocode/plans/` directory if it doesn't exist
   - Save the plan to `.autocode/plans/<plan-id>.json`
   - Confirm: "Plan saved. Run `/autocode` to start executing plan steps."

7. **On rejection**: Ask what to change, re-spawn the Planner with feedback, or discard.

### List Plans

**Trigger**: `/autocode-plan --list`

Read all `.json` files in `.autocode/plans/` and display:

```
Active Plans:
  plan_add_auth    — Add authentication system     [3/4 steps done]  in_progress
  plan_refactor_db — Refactor database layer        [0/6 steps done]  pending

Completed Plans:
  plan_add_logging — Add structured logging          [5/5 steps done]  completed
```

### Show Plan

**Trigger**: `/autocode-plan --show <plan-id>`

Read `.autocode/plans/<plan-id>.json` and display:

```
Plan: Add authentication system
Status: in_progress
Source: github_issue (GH #25)
Created: 2026-03-09

Steps:
  [x] step_1: Define auth types and interfaces        → PR #30
  [~] step_2: Implement auth middleware                → in progress
  [ ] step_3: Add login/logout route handlers          → blocked by step_2
  [ ] step_4: Add auth tests                           → blocked by step_2, step_3

Progress: 1/4 completed, 1 in progress, 2 pending
```

### Cancel Plan

**Trigger**: `/autocode-plan --cancel <plan-id>`

1. Read the plan file
2. Confirm with the user: "Cancel plan '<title>'? This won't revert any PRs already created."
3. On confirmation, set `status` to `"cancelled"` and save
4. Cancelled plans are not ingested by the orchestrator

## Error Handling

- If `.autocode/plans/` doesn't exist for `--list`, `--show`, or `--cancel`: "No plans found. Create one with `/autocode-plan <description>`"
- If `<plan-id>` doesn't match any file: "Plan '<plan-id>' not found. Run `/autocode-plan --list` to see available plans."
- If planning is disabled in manifest: "Multi-PR planning is disabled. Set `planning.enabled: true` in your manifest."
