# Coherence Architecture

AutoCode uses a 6-layer context contract and adaptive constraint repetition to maintain quality across its multi-agent pipeline.

## Why Repetition

LLMs use causal attention — early tokens can't see later tokens. Critical constraints stated once in a long prompt may not receive sufficient attention. Research shows that repeating the prompt improves non-reasoning model performance without increasing output tokens or latency (Leviathan et al., 2025).

AutoCode applies this selectively: only constraint-bearing content is repeated, and only for non-reasoning models.

## The 6-Layer Contract

Every agent prompt is assembled from 6 layers:

| Layer | Source | Content |
|-------|--------|---------|
| 1. Role | agents/*.md | Identity, capabilities, write constraints |
| 2. Universal | Manifest + runtime | Guardrails, immutables, difficulty, budget |
| 3. Work Item | Work queue | Target, type, type-specific guidance |
| 4. Pipeline | Upstream agents | Scout report, spec, changes, coverage |
| 5. Memory | .autocode/memory/ | Patterns, failures, knowledge graph |
| 6. Constraints | Layers 1+2 extract | Repeated constraints (non-reasoning only) |

## Model Classification

Models are classified as reasoning or non-reasoning:
- **Explicit**: `model_routing.<agent>.reasoning` in the manifest
- **Auto-detect**: Models containing "o1", "o3", "r1", "deepthink", "opus" → reasoning
- **Default**: sonnet → non-reasoning

Layer 6 is applied only to non-reasoning models.

## Adaptive Repetition

Constraint repetition is weighted by historical violation frequency, tracked in `.autocode/memory/constraint_violations.json`.

Scoring: `count × recency_weight × severity_multiplier`
- severity_multiplier: hard_reject = 3, soft_reject = 2, warning = 1
- recency_weight: last 3 cycles = 1.0, decays 0.5 per 3-cycle window

Most-violated constraints appear first in the repetition block. The system automatically stops repeating constraints that aren't violated and emphasizes those that are.

## Agent Output Schemas

Every agent returns structured JSON validated by the orchestrator before handoff. See individual agent files for schemas.

## Prompt Coherence Tests

`test.sh` sections 10-12 verify:
- Each agent contains required constraint keywords
- Each agent defines its output schema
- The orchestrator references all 6 layers and key coherence concepts
