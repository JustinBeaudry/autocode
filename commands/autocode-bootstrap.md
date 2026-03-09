# /autocode-bootstrap — Analyze repo and generate manifest

You are the AutoCode Infra Agent. Your job is to analyze the current repository and generate an `autocode.manifest.json` that serves as the immutable contract for all AutoCode agents.

## Output Format

Start with the branded header:
```
  ┌─────────────────────────────────────┐
  │  AutoCode — Bootstrap               │
  │  Analyzing repository...            │
  └─────────────────────────────────────┘
```

If this is the user's first time using AutoCode (no manifest exists), show a welcome:
```
  Welcome to AutoCode! This command will:
  1. Detect your language, framework, and test infrastructure
  2. Measure current coverage and identify gaps
  3. Generate a manifest contract for the factory agents
  4. Set up the memory directory

  Let's get started.
```

## Steps

### 1. Detect Language and Framework

Search for config files to identify the project:

| File | Language | Framework Detection |
|------|----------|-------------------|
| `package.json` | TypeScript/JavaScript | Check for next, express, react, vue, etc. in dependencies |
| `tsconfig.json` | TypeScript | Confirms TS over JS |
| `pyproject.toml` / `setup.py` / `requirements.txt` | Python | Check for fastapi, django, flask, etc. |
| `Cargo.toml` | Rust | Check for actix, axum, rocket, etc. |
| `go.mod` | Go | Check for gin, echo, fiber, chi, etc. in require |
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

**For Python projects**: Check `pyproject.toml` first, then `setup.cfg`, then `setup.py`:
- Test: `pytest` (check if pytest is in dependencies). Fallback: `python -m pytest`
- Coverage: `pytest --cov=<src_dir> --cov-report=term-missing` (if pytest-cov installed)
- Lint: Check for `ruff` (preferred), `flake8`, or `pylint` in dependencies
- Typecheck: Check for `mypy` or `pyright` in dependencies
- Build: `pip install -e .` or `poetry build` (check for poetry.lock)
- Install: `pip install -r requirements.txt` or `poetry install` or `pip install -e ".[dev]"`

**Coverage output parsing for Python**:
Look for the summary line from coverage.py/pytest-cov:
```
Name                      Stmts   Miss  Cover
---------------------------------------------
src/module.py                50     10    80%
---------------------------------------------
TOTAL                       200     40    80%
```
Parse each row: file path, statements, misses, coverage percentage.

**For Rust projects**: Commands are mostly standard:
- Test: `cargo test`
- Coverage: `cargo tarpaulin --out stdout` (if cargo-tarpaulin installed). Alternative: `cargo llvm-cov`
- Lint: `cargo clippy`
- Typecheck: `cargo check`
- Build: `cargo build`
- Install: N/A (Cargo handles dependencies)

**Coverage output parsing for Rust**:
Tarpaulin output format:
```
|| Tested/Total Lines:
|| src/main.rs: 20/30
|| src/lib.rs: 45/50
||
45.00% coverage, 65/80 lines covered
```
Parse the per-file lines and the total percentage.

**For Go projects**: Check `go.mod` for module path:
- Test: `go test ./...`
- Coverage: `go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out`
- Lint: Check for `golangci-lint` (preferred) or `go vet`
- Typecheck: `go vet ./...` (Go's type checker is part of the compiler)
- Build: `go build ./...`
- Install: `go mod download`

**Coverage output parsing for Go**:
`go tool cover -func` output format:
```
github.com/user/repo/pkg/handler.go:25:    HandleRequest    80.0%
github.com/user/repo/pkg/handler.go:50:    ValidateInput    100.0%
total:                                      (statements)     75.0%
```
Parse each function-level line and the total percentage.

### 4. Install Coverage Tooling (if missing)

If no coverage command was detected, check if coverage tooling can be installed:

**Node.js (vitest)**: Check if `@vitest/coverage-v8` is in devDependencies. If not, ask the user:
> "No coverage tool detected. Install `@vitest/coverage-v8` for accurate coverage tracking? (Recommended)"

If approved, run `npm install -D @vitest/coverage-v8` and set coverage command to `vitest run --coverage`.

**Node.js (jest)**: If jest is the test runner, coverage is built-in: `jest --coverage`.

**Python**: Check for `coverage` or `pytest-cov` in dependencies. If missing, suggest `pip install pytest-cov` (or add `pytest-cov` to dev dependencies in `pyproject.toml`). Set coverage command to `pytest --cov=<src_dir> --cov-report=term-missing`.

**Rust**: Check if `cargo-tarpaulin` is installed (`cargo tarpaulin --version`). If not, suggest `cargo install cargo-tarpaulin` (note: this can take a few minutes to compile). Set coverage command to `cargo tarpaulin --out stdout`.

**Go**: Coverage is built-in, no additional tooling needed. Just use the `-coverprofile` flag: `go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out`.

This step is critical — without real coverage data, the factory guesses at gaps and can't measure improvement.

### 5. Verify Tests Pass

Run the test command once to verify it works. If tests fail, warn the user but continue — the manifest should still be generated.

Use Bash to run the test command. Capture the output.

### 5b. Detect Testing Conventions

Analyze existing test files to record testing patterns:

1. **Find test files**: Use Glob to find files matching `*.test.*`, `*.spec.*`, `*_test.*`, `test_*.*`
2. **Sample 2-3 test files**: Read them to detect:
   - **File pattern**: How test files are named (e.g., `*.test.ts`, `*_test.py`)
   - **Location**: Co-located with source (`src/foo.test.ts`) or in a separate directory (`tests/test_foo.py`, `__tests__/foo.test.ts`)
   - **Assertion style**: What assertion library/style is used (e.g., `expect/toBe` for vitest/jest, `assert` for pytest, `assert_eq!` for Rust)
   - **Structure**: How tests are organized (e.g., `describe/it`, `test()`, `#[test]`, `def test_`)
   - **Helpers**: Any shared test utilities or fixtures (e.g., `src/test/helpers.ts`, `conftest.py`, `test_utils.rs`)
3. **Record in manifest**: Store detected patterns in the `testing` section (see Step 10)

### 6. Run Coverage

If a coverage command exists (detected or just installed), run it. Parse the output to extract:
- Overall coverage percentages (statements, branches, functions, lines)
- Per-file coverage to identify gaps

Coverage output parsing by tool:

- **v8/istanbul** (Node.js): Look for the summary table at the end with columns: `% Stmts`, `% Branch`, `% Funcs`, `% Lines`. Parse the `All files` row for totals.

- **coverage.py / pytest-cov** (Python): Look for the table with columns: `Name`, `Stmts`, `Miss`, `Cover`. Parse each file row for per-file coverage. The `TOTAL` row has the overall percentage. If `--cov-report=term-missing` was used, there is also a `Missing` column with uncovered line ranges.

- **tarpaulin** (Rust): Look for per-file lines like `|| src/main.rs: 20/30` for tested/total lines. The final summary line has the format `XX.XX% coverage, N/M lines covered`. Parse both per-file and total.

- **go tool cover -func** (Go): Each line shows `file:line: FuncName percentage%`. The last line starting with `total:` has the overall statement coverage. Parse each function-level line for per-file gaps and the total for overall coverage.

**IMPORTANT**: Store the raw coverage output format in the manifest so the orchestrator knows how to parse it during cycles. The `coverage.tool` field tells downstream agents which parser to use:
- `"v8"` or `"istanbul"`: Look for the table with `% Stmts | % Branch | % Funcs | % Lines` columns
- `"pytest-cov"`: Look for `Name | Stmts | Miss | Cover` columns
- `"tarpaulin"`: Look for `|| file: tested/total` lines
- `"go-cover"`: Look for `file:line: FuncName percentage%` lines

**IMPORTANT**: If coverage tooling is not available and the user declined to install it, do NOT estimate coverage by reading code. Set coverage to null and note it. Estimated coverage is misleading — it's better to have no data than wrong data.

### 7. Identify Coverage Gaps

From the coverage output, find files with the lowest coverage. Sort them by coverage percentage (ascending). These become the `gaps` array in the manifest, with priority = rank.

Filter out:
- Test files themselves
- Config files
- Type definition files (`.d.ts`)
- Generated files

### 7b. Classify Gap Files

For each file in the coverage gaps array, classify its type and estimate complexity:

**Types** (inspect the file's exports and structure):
- `pure_function`: File exports only pure functions (no side effects, no external calls)
- `utility`: Helper/utility functions, may have light side effects
- `handler`: Request handler, route handler, or controller
- `service`: Business logic with external dependencies (DB, API, cache)
- `middleware`: Middleware, interceptors, or pipeline stages
- `infrastructure`: Database, cache, queue, or external service wrappers

**Complexity** (based on dependencies and structure):
- `low`: < 100 lines, few imports, no external dependencies
- `medium`: 100-300 lines, some imports, light external dependencies
- `high`: 300+ lines, many imports, heavy external dependencies or complex logic

Add `type` and `complexity` fields to each gap entry:
```json
{ "file": "src/utils/parser.ts", "coverage": 15, "priority": 1, "type": "pure_function", "complexity": "low" }
```

This classification helps the orchestrator route work items to the right difficulty level and skip files that are too complex for the current level.

### 8. Detect CI

Check for CI configuration:
- `.github/workflows/*.yml` → GitHub Actions
- `.gitlab-ci.yml` → GitLab CI
- `.circleci/config.yml` → CircleCI
- `Jenkinsfile` → Jenkins

### 9. Detect Default Branch

Run `git remote show origin 2>/dev/null | grep "HEAD branch"` to detect the default branch. Fall back to checking if `main` or `master` exists.

### 10. Generate Manifest

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
    "scout": "sonnet",
    "architect": "sonnet",
    "builder": "opus",
    "tester": "sonnet",
    "reviewer": "opus"
  },
  "brain": {
    "knowledge_graph": true,
    "pattern_database": true,
    "human_feedback": true,
    "pattern_retention_days": 90
  },
  "ci": {
    "auto_fix": true,
    "max_fix_attempts": 2,
    "fixable_categories": ["test_failure", "type_error", "lint_error", "build_error"]
  },
  "planning": {
    "enabled": true,
    "max_steps_per_plan": 10,
    "auto_plan_issues": false
  },
  "budget": {
    "session_max_usd": 5.00,
    "cycle_max_usd": 2.00,
    "warn_at_percent": 80
  },
  "daemon": {
    "enabled": false,
    "schedule": "0 */6 * * *",
    "max_cycles_per_run": 5,
    "daily_budget_usd": 10.00,
    "deploy_windows": [],
    "notifications": {
      "on_failure": "github_issue",
      "on_success": "none",
      "on_budget_exceeded": "github_issue"
    }
  },
  "discovery": {
    "enabled": false,
    "modules": {
      "untested_changes": true,
      "complexity_hotspots": true,
      "dependency_audit": true,
      "stale_todos": true
    },
    "complexity_threshold_lines": 300,
    "todo_age_days": 30,
    "max_items_per_module": 5
  },
  "work_sources": {
    "coverage_gaps": true,
    "github_issues": {
      "enabled": false,
      "labels": ["autocode"],
      "exclude_labels": ["wontfix", "duplicate"]
    },
    "backlog": true,
    "pr_reviews": true,
    "tech_debt": false
  },
  "testing": {
    "file_pattern": "<detected>",
    "location": "<detected: co-located | separate>",
    "assertion_style": "<detected>",
    "structure": "<detected>",
    "helpers": []
  }
}
```

### 10b. Prompt for Work Sources

Ask the user about enabling additional work sources:

"Enable GitHub Issues integration? Issues labeled 'autocode' will be picked up as work items. (Default: no)"

If yes, set `work_sources.github_issues.enabled` to `true`.

"Enable tech debt scanning? AutoCode will scan for TODO/FIXME comments and create low-priority work items. (Default: no)"

If yes, set `work_sources.tech_debt` to `true`.

### 11. Present for Review

Display the generated manifest to the user in a code block. Ask them to review it and confirm before saving.

Highlight:
- Detected language/framework
- Test command that will be used
- Coverage baselines
- Top 5 coverage gaps (these will be the first targets)
- Any values that were defaulted (couldn't auto-detect)

### 12. Save

On user approval, write `autocode.manifest.json` to the repository root.

Also create the `.autocode/memory/` directory with seeded memory files (not empty — Claude Code requires reading a file before writing, so pre-populate with a record template):
- `.autocode/memory/fixes.md` — header + "No fixes yet."
- `.autocode/memory/failures.md` — header + "No failures yet."
- `.autocode/memory/velocity.md` — header + "No cycles yet."
- `.autocode/memory/coverage.md` — header + "No coverage data yet."
- `.autocode/memory/lessons.md` — header + "No lessons yet."
- `.autocode/memory/costs.md` — header + "No cost data yet."
- `.autocode/memory/knowledge.json` — `{"version": 1, "last_updated": null, "files": {}, "modules": {}}`
- `.autocode/memory/patterns.json` — `{"version": 1, "patterns": []}`
- `.autocode/memory/ci_patterns.json` — `{"version": 1, "patterns": [], "stats": {"total_failures": 0, "auto_fixed": 0, "reverted": 0, "fix_rate": 0}}`
- `.autocode/memory/feedback_log.json` — `{"ingested_prs": [], "last_check": null}`

Add `.autocode/` and `autocode.manifest.json` to `.gitignore` if not already present.

### 13. Create GitHub Label

Create the `autocode` label on the repo so PRs get tagged:

```bash
gh label create autocode --description "Automated by AutoCode" --color "0E8A16" 2>/dev/null || true
```

## Error Handling

- If no test command is detected, warn the user and ask them to specify one
- If tests fail, note it in the manifest but continue
- If coverage can't be parsed, set coverage to null and note it
- If git remote doesn't exist, ask user for the default branch name
