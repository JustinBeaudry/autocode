# /autocode-bootstrap — Analyze repo and generate manifest

You are the AutoCode Infra Agent. Your job is to analyze the current repository and generate an `autocode.manifest.json` that serves as the immutable contract for all AutoCode agents.

## Steps

### 1. Detect Language and Framework

Search for config files to identify the project:

| File | Language | Framework Detection |
|------|----------|-------------------|
| `package.json` | TypeScript/JavaScript | Check for next, express, react, vue, etc. in dependencies |
| `tsconfig.json` | TypeScript | Confirms TS over JS |
| `pyproject.toml` / `setup.py` / `requirements.txt` | Python | Check for fastapi, django, flask, etc. |
| `Cargo.toml` | Rust | Check for actix, axum, rocket, etc. |
| `go.mod` | Go | Check for gin, echo, fiber, etc. |
| `pom.xml` / `build.gradle` | Java/Kotlin | Check for spring, etc. |

Use Glob to find these files, then Read to inspect them.

### 2. Detect Monorepo

Check for workspace configuration:
- `package.json` → `workspaces` field
- `pnpm-workspace.yaml`
- `lerna.json`
- `Cargo.toml` → `[workspace]`

### 3. Detect Commands

Find the test, build, lint, and typecheck commands:

**For Node.js projects**: Read `package.json` scripts section. Look for:
- `test` → test command
- `test:coverage` or `coverage` → coverage command
- `lint` → lint command
- `typecheck` or `tsc` → typecheck command
- `build` → build command
- Install is typically `npm ci` or `pnpm install` or `yarn install` (check lockfile)

**For Python projects**: Check `pyproject.toml` for:
- `[tool.pytest]` → `pytest`
- `[tool.coverage]` → `pytest --cov`
- `[tool.ruff]` or `[tool.flake8]` → lint
- `[tool.mypy]` → typecheck

**For Rust projects**: Commands are typically standard (`cargo test`, `cargo build`, etc.)

### 4. Verify Tests Pass

Run the test command once to verify it works. If tests fail, warn the user but continue — the manifest should still be generated.

Use Bash to run the test command. Capture the output.

### 5. Run Coverage (if available)

If a coverage command was detected, run it. Parse the output to extract:
- Overall coverage percentages (statements, branches, functions, lines)
- Per-file coverage to identify gaps

Coverage output parsing by tool:
- **v8/istanbul**: Look for the summary table at the end
- **coverage.py**: Look for the summary line
- **tarpaulin**: Look for the final percentage

### 6. Identify Coverage Gaps

From the coverage output, find files with the lowest coverage. Sort them by coverage percentage (ascending). These become the `gaps` array in the manifest, with priority = rank.

Filter out:
- Test files themselves
- Config files
- Type definition files (`.d.ts`)
- Generated files

### 7. Detect CI

Check for CI configuration:
- `.github/workflows/*.yml` → GitHub Actions
- `.gitlab-ci.yml` → GitLab CI
- `.circleci/config.yml` → CircleCI
- `Jenkinsfile` → Jenkins

### 8. Detect Default Branch

Run `git remote show origin 2>/dev/null | grep "HEAD branch"` to detect the default branch. Fall back to checking if `main` or `master` exists.

### 9. Generate Manifest

Assemble the `autocode.manifest.json` with all detected values. Use sensible defaults for anything not detected:

```json
{
  "version": 1,
  "repo": {
    "name": "<detected>",
    "language": "<detected>",
    "framework": "<detected or null>",
    "monorepo": false,
    "default_branch": "<detected>"
  },
  "commands": {
    "install": "<detected or null>",
    "test": "<detected>",
    "coverage": "<detected or null>",
    "typecheck": "<detected or null>",
    "lint": "<detected or null>",
    "build": "<detected or null>"
  },
  "coverage": {
    "tool": "<detected or null>",
    "current": { "statements": 0, "branches": 0, "functions": 0, "lines": 0 },
    "targets": { "statements": 80, "branches": 70, "functions": 80, "lines": 80 },
    "gaps": []
  },
  "scoring": {
    "formula": "(merge_rate * 0.4) + (coverage_delta * 0.3) + ((1 - regression_rate) * 0.3)",
    "weights_rationale": "Merge rate highest because shipped > written"
  },
  "guardrails": {
    "immutable_patterns": ["*.config.*", "*.env*", ".github/**", "autocode.manifest.json"],
    "max_files_per_pr": 5,
    "max_lines_changed": 200
  },
  "time_budgets": {
    "scout_seconds": 180,
    "architect_seconds": 180,
    "builder_seconds": 600,
    "tester_seconds": 600,
    "reviewer_seconds": 300,
    "cycle_max_seconds": 1800
  },
  "difficulty": {
    "current_level": 1,
    "levels": {
      "1": "Pure function coverage (no mocking)",
      "2": "Utility/helper coverage (light mocking)",
      "3": "Fix existing failing tests",
      "4": "Integration coverage (DB, API mocks)",
      "5": "Feature implementation from tickets",
      "6": "Refactoring with behavior preservation"
    },
    "advance_when": "3 consecutive successful cycles at current level"
  },
  "model_routing": {
    "scout": "haiku",
    "architect": "sonnet",
    "builder": "opus",
    "tester": "sonnet",
    "reviewer": "opus"
  }
}
```

### 10. Present for Review

Display the generated manifest to the user in a code block. Ask them to review it and confirm before saving.

Highlight:
- Detected language/framework
- Test command that will be used
- Coverage baselines
- Top 5 coverage gaps (these will be the first targets)
- Any values that were defaulted (couldn't auto-detect)

### 11. Save

On user approval, write `autocode.manifest.json` to the repository root.

Also create the `.autocode/memory/` directory with empty memory files:
- `.autocode/memory/fixes.md` — header only
- `.autocode/memory/failures.md` — header only
- `.autocode/memory/velocity.md` — header only
- `.autocode/memory/coverage.md` — header only
- `.autocode/memory/lessons.md` — header only

Add `.autocode/` to `.gitignore` if not already present.

## Error Handling

- If no test command is detected, warn the user and ask them to specify one
- If tests fail, note it in the manifest but continue
- If coverage can't be parsed, set coverage to null and note it
- If git remote doesn't exist, ask user for the default branch name
