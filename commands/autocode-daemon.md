# /autocode-daemon — Daemon Mode (GitHub Actions)

Run AutoCode on a schedule via GitHub Actions with budget controls.

## Output Format

Start with the branded header:
```
  ┌─────────────────────────────────────┐
  │  AutoCode — Daemon                  │
  │  <repo name> · v4.1                 │
  └─────────────────────────────────────┘
```

## Usage

```
/autocode-daemon setup     → Generate GitHub Actions workflow + configure
/autocode-daemon status    → Show daemon status (last run, next run, budget)
/autocode-daemon pause     → Disable the cron schedule
/autocode-daemon resume    → Re-enable the cron schedule
/autocode-daemon budget    → Show/set spending limits
```

## Behavior

### Setup

**Trigger**: `/autocode-daemon setup`

1. **Check prerequisites**:
   - `autocode.manifest.json` exists → if not: "Run `/autocode-bootstrap` first."
   - `gh` CLI authenticated → if not: "Run `gh auth login` first."
   - `.github/workflows/` directory exists → create if needed

2. **Ask for configuration**:
   - Schedule (default: every 6 hours — `0 */6 * * *`)
   - Max cycles per run (default: 5)
   - Daily budget in USD (default: $10/day)
   - Notification preference: GitHub Issue on failure (default), none, or PR comment

3. **Generate workflow file** at `.github/workflows/autocode-daemon.yml`:

```yaml
name: AutoCode Daemon
on:
  schedule:
    - cron: '<configured schedule>'
  workflow_dispatch:
    inputs:
      max_cycles:
        description: 'Maximum cycles to run'
        default: '<configured max>'

concurrency:
  group: autocode-daemon
  cancel-in-progress: false

jobs:
  autocode:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    permissions:
      contents: write
      pull-requests: write
      issues: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code

      - name: Restore AutoCode state
        uses: actions/cache@v4
        with:
          path: .autocode/memory
          key: autocode-memory-${{ github.sha }}
          restore-keys: autocode-memory-

      - name: Budget check
        id: budget
        run: |
          DAILY_SPENT=$(python3 -c "
          import re, sys
          from datetime import date
          today = str(date.today())
          total = 0.0
          try:
            with open('.autocode/memory/costs.md') as f:
              for line in f:
                if today in line and 'Estimated cost:' in line:
                  m = re.search(r'\\\$([0-9.]+)', line)
                  if m: total += float(m.group(1))
          except FileNotFoundError:
            pass
          print(f'{total:.2f}')
          ")
          BUDGET="${{ vars.AUTOCODE_DAILY_BUDGET || '<configured budget>' }}"
          echo "spent=$DAILY_SPENT" >> $GITHUB_OUTPUT
          echo "budget=$BUDGET" >> $GITHUB_OUTPUT
          if (( $(echo "$DAILY_SPENT >= $BUDGET" | bc -l) )); then
            echo "over_budget=true" >> $GITHUB_OUTPUT
            echo "::warning::Daily budget exceeded: \$$DAILY_SPENT / \$$BUDGET"
          else
            echo "over_budget=false" >> $GITHUB_OUTPUT
          fi

      - name: Calculate remaining budget
        if: steps.budget.outputs.over_budget != 'true'
        id: remaining
        run: |
          REMAINING=$(echo "${{ steps.budget.outputs.budget }} - ${{ steps.budget.outputs.spent }}" | bc -l)
          echo "budget_remaining=$REMAINING" >> $GITHUB_OUTPUT

      - name: Run AutoCode
        if: steps.budget.outputs.over_budget != 'true'
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          claude -p --dangerously-skip-permissions \
            --max-turns 200 \
            --max-budget-usd "${{ steps.remaining.outputs.budget_remaining }}" \
            "/autocode"

      - name: Save AutoCode state
        if: always()
        uses: actions/cache/save@v4
        with:
          path: .autocode/memory
          key: autocode-memory-${{ github.sha }}-${{ github.run_id }}

      - name: Notify on failure
        if: failure()
        run: |
          gh issue create \
            --title "AutoCode Daemon: Run failed $(date +%Y-%m-%d)" \
            --body "The AutoCode daemon run failed. Check the [workflow run](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}) for details." \
            --label "autocode,daemon"
```

4. **Update manifest**: Add `daemon` section to `autocode.manifest.json` with the configured values.

5. **Remind about secrets**:
   ```
   Setup complete! One manual step required:

   Add your Anthropic API key as a GitHub secret:
     gh secret set ANTHROPIC_API_KEY

   Optionally set a daily budget override as a repository variable:
     gh variable set AUTOCODE_DAILY_BUDGET --body "10.00"
   ```

6. **Offer to commit**: "Commit the workflow file? This will enable the daemon on the configured schedule."

### Status

**Trigger**: `/autocode-daemon status`

1. Read `autocode.manifest.json` for daemon config
2. Read `.autocode/daemon_state.json` if it exists
3. Check workflow status:
   ```bash
   gh run list --workflow autocode-daemon.yml --limit 3 --json status,conclusion,createdAt,databaseId
   ```
4. Display:
   ```
   AutoCode Daemon Status:
     Enabled: yes
     Schedule: Every 6 hours (0 */6 * * *)
     Max cycles/run: 5
     Daily budget: $10.00

   Last Run:
     Time: 2026-03-09T06:00:00Z
     Result: success
     Cycles: 5
     PRs: #30, #31
     Cost: $4.50

   Budget:
     Today: $4.50 / $10.00 (45%)
     Total daemon runs: 42

   Next Run: ~2026-03-09T12:00:00Z
   ```

### Pause

**Trigger**: `/autocode-daemon pause`

1. Disable the workflow:
   ```bash
   gh workflow disable autocode-daemon.yml
   ```
2. Update `manifest.daemon.enabled` to `false`
3. Confirm: "Daemon paused. Run `/autocode-daemon resume` to re-enable."

### Resume

**Trigger**: `/autocode-daemon resume`

1. Enable the workflow:
   ```bash
   gh workflow enable autocode-daemon.yml
   ```
2. Update `manifest.daemon.enabled` to `true`
3. Confirm: "Daemon resumed. Next run: <next scheduled time>"

### Budget

**Trigger**: `/autocode-daemon budget`

1. Read costs from `.autocode/memory/costs.md`
2. Read daemon state from `.autocode/daemon_state.json`
3. Display:
   ```
   Budget Overview:
     Daily limit: $10.00
     Spent today: $4.50
     Remaining: $5.50

   History (last 7 days):
     Mar 09: $4.50 (5 cycles, 2 PRs)
     Mar 08: $8.20 (5 cycles, 3 PRs)
     Mar 07: $3.10 (5 cycles, 1 PR)
     ...

   To change the daily budget:
     - Edit manifest.daemon.daily_budget_usd
     - Or set repository variable: gh variable set AUTOCODE_DAILY_BUDGET --body "20.00"
   ```

## Daemon State File

The orchestrator reads/writes `.autocode/daemon_state.json` at the start and end of each daemon run:

```json
{
  "last_run": "2026-03-09T06:00:00Z",
  "last_run_result": "success",
  "last_run_cycles": 5,
  "last_run_prs": ["#30", "#31"],
  "today_spent_usd": 4.50,
  "total_daemon_runs": 42,
  "consecutive_empty_runs": 0
}
```

## Error Handling

- If workflow file already exists: "Daemon workflow already exists. Overwrite? (This will reset the configuration.)"
- If `gh` is not authenticated: "GitHub CLI not authenticated. Run `gh auth login` first."
- If no manifest exists: "Run `/autocode-bootstrap` first."
- If pausing fails: Check if the workflow name is correct and the user has admin permissions
