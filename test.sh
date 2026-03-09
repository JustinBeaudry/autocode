#!/usr/bin/env bash
# AutoCode Test Suite — validates structure, schema, and cross-references
# Zero external dependencies (bash + python3 stdlib only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
WARN=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ○ $1 (warning)"; WARN=$((WARN + 1)); }

echo ""
echo "  ┌─────────────────────────────────────┐"
echo "  │  AutoCode — Test Suite              │"
echo "  │  v4.1                               │"
echo "  └─────────────────────────────────────┘"
echo ""

# ── 1. JSON Validity ──────────────────────────────────────────────────
echo "1. JSON Validity"
for f in "$ROOT"/examples/*.json "$ROOT"/schemas/*.json "$ROOT"/tests/*.json; do
  if [ -f "$f" ]; then
    name=$(basename "$f")
    if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
      pass "$name"
    else
      fail "$name — invalid JSON"
    fi
  fi
done
echo ""

# ── 2. Schema Validation ─────────────────────────────────────────────
echo "2. Schema Validation (structural)"
if python3 "$ROOT/tests/validate-schema.py" 2>/dev/null; then
  pass "All manifests validate"
else
  fail "Schema validation failed (run: python3 tests/validate-schema.py)"
fi
echo ""

# ── 3. Agent Structure ───────────────────────────────────────────────
echo "3. Agent Structure"
for f in "$ROOT"/agents/*.md; do
  name=$(basename "$f" .md)
  missing=""
  # Check for required sections (at least one of these patterns)
  if ! grep -q "^## Constraints\|^## Input\|^## Output\|^## Task\|^## Time Budget" "$f" 2>/dev/null; then
    # More lenient: check for any H2 sections
    h2_count=$(grep -c "^## " "$f" 2>/dev/null || echo "0")
    if [ "$h2_count" -lt 2 ]; then
      missing="needs more structured sections"
    fi
  fi
  if [ -n "$missing" ]; then
    warn "agents/$name.md — $missing"
  else
    pass "agents/$name.md"
  fi
done
echo ""

# ── 4. Command Structure ─────────────────────────────────────────────
echo "4. Command Structure"
for f in "$ROOT"/commands/*.md; do
  name=$(basename "$f" .md)
  if grep -q "^## Steps\|^## Usage\|^## Behavior\|^## Output Format" "$f" 2>/dev/null; then
    pass "commands/$name.md"
  else
    fail "commands/$name.md — missing ## Steps, ## Usage, ## Behavior, or ## Output Format"
  fi
done
echo ""

# ── 5. Cross-Reference Integrity ─────────────────────────────────────
echo "5. Cross-Reference Integrity"

# 5a. Every agent referenced in docs/agents.md exists in agents/
if [ -f "$ROOT/docs/agents.md" ]; then
  agents_in_docs=$(grep -o 'agents/[a-z_-]*\.md' "$ROOT/docs/agents.md" 2>/dev/null | sort -u)
  for ref in $agents_in_docs; do
    if [ -f "$ROOT/$ref" ]; then
      pass "docs/agents.md → $ref exists"
    else
      fail "docs/agents.md references $ref but file not found"
    fi
  done
fi

# 5b. Every command in README command table exists in commands/
if [ -f "$ROOT/README.md" ]; then
  commands_in_readme=$(grep -oE '/autocode[a-z-]*' "$ROOT/README.md" 2>/dev/null | sort -u)
  for cmd in $commands_in_readme; do
    cmd_file="$ROOT/commands/${cmd#/}.md"
    if [ -f "$cmd_file" ]; then
      pass "README → $cmd exists"
    else
      # Some commands are subcommands (e.g., /autocode-daemon setup)
      base_cmd=$(echo "$cmd" | sed 's/ .*//')
      base_file="$ROOT/commands/${base_cmd#/}.md"
      if [ -f "$base_file" ]; then
        pass "README → $cmd (subcommand of $base_cmd)"
      else
        warn "README references $cmd — no matching command file"
      fi
    fi
  done
fi

# 5c. Agent count in docs/agents.md matches actual count
if [ -f "$ROOT/docs/agents.md" ]; then
  actual_count=$(ls "$ROOT"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
  doc_count=$(grep -oE '[0-9]+ specialized agents' "$ROOT/docs/agents.md" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
  if [ "$doc_count" != "0" ] && [ "$actual_count" != "$doc_count" ]; then
    warn "docs/agents.md says $doc_count agents, but $actual_count exist"
  else
    pass "Agent count: $actual_count agents"
  fi
fi
echo ""

# ── 6. Install Script ────────────────────────────────────────────────
echo "6. Install Script"
if [ -f "$ROOT/install.sh" ]; then
  if bash -n "$ROOT/install.sh" 2>/dev/null; then
    pass "install.sh — syntax valid"
  else
    fail "install.sh — syntax error"
  fi
else
  fail "install.sh not found"
fi
echo ""

# ── 7. Plan File Format ──────────────────────────────────────────────
echo "7. Plan File Format"
if [ -f "$ROOT/tests/sample-plan.json" ]; then
  if python3 -c "
import json, sys
with open('$ROOT/tests/sample-plan.json') as f:
    p = json.load(f)
required = ['id', 'title', 'status', 'steps']
missing = [k for k in required if k not in p]
if missing:
    print(f'Missing: {missing}')
    sys.exit(1)
for i, s in enumerate(p['steps']):
    for k in ['id', 'title', 'work_type', 'target_files', 'status', 'blocked_by']:
        if k not in s:
            print(f'Step {i} missing: {k}')
            sys.exit(1)
" 2>/dev/null; then
    pass "sample-plan.json — valid structure"
  else
    fail "sample-plan.json — invalid plan structure"
  fi
else
  fail "tests/sample-plan.json not found"
fi
echo ""

# ── 8. Manifest Completeness ─────────────────────────────────────────
echo "8. Manifest Completeness"
EXPECTED_SECTIONS="version repo commands coverage guardrails time_budgets difficulty model_routing brain ci planning daemon discovery budget work_sources testing"
for f in "$ROOT"/examples/*.json; do
  name=$(basename "$f")
  missing_sections=""
  for section in $EXPECTED_SECTIONS; do
    if ! python3 -c "import json; d=json.load(open('$f')); assert '$section' in d" 2>/dev/null; then
      missing_sections="$missing_sections $section"
    fi
  done
  if [ -n "$missing_sections" ]; then
    fail "$name — missing sections:$missing_sections"
  else
    pass "$name — all sections present"
  fi
done
echo ""

# ── 9. Link Integrity ────────────────────────────────────────────────
echo "9. Link Integrity"
# Check markdown links to local files in README and docs
for doc in "$ROOT/README.md" "$ROOT"/docs/*.md; do
  if [ -f "$doc" ]; then
    docname=$(basename "$doc")
    # Extract relative file links (not URLs, not anchors)
    links=$(grep -oE '\[.*?\]\(([^)#]+)\)' "$doc" 2>/dev/null | grep -oE '\(([^)#]+)\)' | tr -d '()' | grep -v '^http' | grep -v '^mailto' || true)
    for link in $links; do
      docdir=$(dirname "$doc")
      target="$docdir/$link"
      if [ -f "$target" ] || [ -d "$target" ]; then
        pass "$docname → $link"
      else
        # Try from repo root
        if [ -f "$ROOT/$link" ] || [ -d "$ROOT/$link" ]; then
          pass "$docname → $link (from root)"
        else
          warn "$docname → $link not found"
        fi
      fi
    done
  fi
done
echo ""

# ── Summary ───────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
