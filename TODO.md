# AutoCode — Backlog

## Status Key
- `[ ]` — Todo
- `[~]` — In Progress
- `[x]` — Done

---

## v1 — Core Pipeline ✅

All 16 tickets completed. See git history for details.

---

## v2 — Engineering Department

### Completed

- [x] Work queue system — multi-source ingestion (focus, GitHub Issues, coverage gaps, backlog, PR reviews, tech debt)
- [x] Pipeline routing — configures agent pipeline per work type
- [x] PR review response loop — address review comments, post summary
- [x] Work type guidance for Builder (bugfix, feature, refactor, docs, dependency, review_response)
- [x] Scout accepts work items (not just target files)
- [x] Lessons section added to Architect, Tester, Reviewer
- [x] Architect spec passed to Reviewer (spec compliance) and Tester (edge case coverage)
- [x] Manifest: work_sources, testing conventions, gap type/complexity classification
- [x] Bootstrap: test convention detection (Step 5b), file classification (Step 7b), work sources prompting (Step 10b)
- [x] /autocode-focus command — priority queue management
- [x] /autocode-next command — dry run preview
- [x] Difficulty levels rethought — work type filtering by level
- [x] All docs, examples, schema, README updated

---

## v3 — Persistent Brain + CI-Aware Shipping

### Completed

- [x] Knowledge graph (`.autocode/memory/knowledge.json`) — Scout caches file analysis across sessions
- [x] Pattern database (`.autocode/memory/patterns.json`) — weighted, indexed patterns replace unstructured lesson scanning
- [x] Human feedback loop — extracts patterns from human PR reviews on merged/closed PRs
- [x] CI log parsing — reads CI logs, categorizes failures (test, type, lint, build, env, unknown)
- [x] CI auto-fix — spawns Builder with `ci_fix` work type before reverting
- [x] CI pattern database (`.autocode/memory/ci_patterns.json`) — tracks failure signatures and fix history
- [x] Manifest `brain` config section — knowledge_graph, pattern_database, human_feedback, retention
- [x] Manifest `ci` config section — auto_fix, max_fix_attempts, fixable_categories
- [x] Builder `ci_fix` work type — minimal fix guidance for CI failures
- [x] All docs, examples, schema, README updated

---

## v4 — Multi-PR Planning, Daemon Mode, Proactive Discovery

### Completed

- [x] Multi-PR planning — Planner agent decomposes large tasks into dependency graph of atomic PRs
- [x] Plan file format (`.autocode/plans/<plan-id>.json`) with blocked_by dependency graph
- [x] `/autocode-plan` command — create, list, show, cancel plans
- [x] Orchestrator ingests unblocked plan steps as high-priority work items
- [x] Plan status updates on step completion/failure
- [x] Daemon mode — GitHub Actions workflow with cron schedule and budget controls
- [x] `/autocode-daemon` command — setup, status, pause, resume, budget
- [x] Daemon state persistence via GitHub Actions cache
- [x] Budget check in stop conditions (daily spending limit)
- [x] Proactive discovery — Discoverer agent with 4 modules (untested changes, complexity, deps, TODOs)
- [x] `/autocode-discover` command — manual discovery with dry-run mode
- [x] Discovery items ingested as work source between backlog and tech debt
- [x] Manifest schema: planning, daemon, discovery sections
- [x] Bootstrap: planning, daemon, discovery added to manifest template
- [x] All docs, examples, schema, README, CLAUDE.md updated

### Future Ideas

- [ ] GitHub Issue auto-close on PR merge (link issue to PR)
- [ ] Slack/webhook notifications on cycle completion
- [ ] Custom work sources (user-defined ingestion scripts)
- [ ] Multi-repo orchestration (run across several repos from one session)
- [ ] Auto-merge for trusted repos (configurable confidence threshold)
- [ ] Plan visualization (mermaid diagram generation)
- [ ] Daemon analytics dashboard (cost per PR over time, success rate trends)
- [ ] Cross-plan dependency tracking (plan A step blocks plan B step)
