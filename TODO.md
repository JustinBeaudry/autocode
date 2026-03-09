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

### Future Ideas

- [ ] GitHub Issue auto-close on PR merge (link issue to PR)
- [ ] Slack/webhook notifications on cycle completion
- [ ] Custom work sources (user-defined ingestion scripts)
- [ ] Multi-repo orchestration (run across several repos from one session)
- [ ] Auto-merge for trusted repos (configurable confidence threshold)
- [ ] Dependency vulnerability scanning via `npm audit` / `cargo audit` / `pip-audit`
