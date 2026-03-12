#!/usr/bin/env python3
"""Validate AutoCode example manifests against basic structural rules.

Uses only stdlib (json) — no external dependencies required.
Checks that all example manifests have the required top-level sections
and that their values match expected types.
"""

import json
import sys
import os

REQUIRED_TOP_LEVEL = ["version", "repo", "commands", "guardrails"]
EXPECTED_TOP_LEVEL = [
    "version", "repo", "commands", "coverage", "guardrails",
    "time_budgets", "difficulty", "model_routing", "brain", "ci",
    "planning", "daemon", "discovery", "budget", "work_sources", "testing"
]

REQUIRED_REPO_FIELDS = ["name", "language", "default_branch"]
REQUIRED_COMMANDS_FIELDS = ["test"]

VALID_LANGUAGES = [
    "typescript", "javascript", "python", "rust", "go",
    "java", "kotlin", "swift", "ruby", "php", "csharp", "cpp"
]


def validate_manifest(filepath):
    """Validate a single manifest JSON file. Returns list of errors."""
    errors = []

    try:
        with open(filepath) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return [f"Invalid JSON: {e}"]

    # Check required top-level keys
    for key in REQUIRED_TOP_LEVEL:
        if key not in data:
            errors.append(f"Missing required key: {key}")

    # Check expected top-level keys (warn, don't fail)
    missing_expected = [k for k in EXPECTED_TOP_LEVEL if k not in data]
    if missing_expected:
        errors.append(f"Missing expected sections: {', '.join(missing_expected)}")

    # Validate version
    if data.get("version") != 1:
        errors.append(f"Expected version=1, got {data.get('version')}")

    # Validate repo
    repo = data.get("repo", {})
    for field in REQUIRED_REPO_FIELDS:
        if field not in repo:
            errors.append(f"repo.{field} is missing")
    if repo.get("language") and repo["language"] not in VALID_LANGUAGES:
        errors.append(f"repo.language '{repo['language']}' not in valid list")

    # Validate commands
    commands = data.get("commands", {})
    for field in REQUIRED_COMMANDS_FIELDS:
        if field not in commands:
            errors.append(f"commands.{field} is missing")

    # Validate budget section exists and has expected fields
    budget = data.get("budget")
    if budget is not None:
        if not isinstance(budget, dict):
            errors.append("budget should be an object")
        else:
            for field in ["session_max_usd", "cycle_max_usd", "warn_at_percent"]:
                if field not in budget:
                    errors.append(f"budget.{field} is missing")
            if "session_max_usd" in budget and budget["session_max_usd"] < 0.50:
                errors.append(f"budget.session_max_usd too low: {budget['session_max_usd']}")

    # Validate model_routing (supports string or {model, reasoning} object)
    routing_raw = data.get("model_routing")
    if routing_raw is None:
        routing = {}
    elif isinstance(routing_raw, dict):
        routing = routing_raw
    else:
        errors.append(f"model_routing should be an object or null, got {type(routing_raw).__name__}")
        routing = {}
    for agent, value in routing.items():
        if isinstance(value, str):
            model = value
        elif isinstance(value, dict):
            model = value.get("model")
            if model is None:
                errors.append(f"model_routing.{agent} object missing 'model' field")
                continue
            reasoning = value.get("reasoning")
            if reasoning is not None and not isinstance(reasoning, bool):
                errors.append(f"model_routing.{agent}.reasoning should be boolean, got {type(reasoning).__name__}")
        else:
            errors.append(f"model_routing.{agent} should be a string or object, got {type(value).__name__}")
            continue
        valid_models = ["haiku", "sonnet", "opus"]
        if model not in valid_models:
            errors.append(f"model_routing.{agent} has invalid model: {model}")

    # Validate coverage gaps structure
    coverage = data.get("coverage")
    if coverage and isinstance(coverage, dict):
        gaps = coverage.get("gaps", [])
        for i, gap in enumerate(gaps):
            if "file" not in gap:
                errors.append(f"coverage.gaps[{i}] missing 'file'")
            if "coverage" not in gap:
                errors.append(f"coverage.gaps[{i}] missing 'coverage'")
            if "priority" not in gap:
                errors.append(f"coverage.gaps[{i}] missing 'priority'")

    return errors


def validate_plan(filepath):
    """Validate a plan JSON file structure. Returns list of errors."""
    errors = []

    try:
        with open(filepath) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return [f"Invalid JSON: {e}"]

    for field in ["id", "title", "status", "steps"]:
        if field not in data:
            errors.append(f"Missing required field: {field}")

    steps = data.get("steps", [])
    if not isinstance(steps, list):
        errors.append("steps should be an array")
        return errors

    step_ids = set()
    for i, step in enumerate(steps):
        for field in ["id", "title", "work_type", "target_files", "status", "blocked_by"]:
            if field not in step:
                errors.append(f"steps[{i}] missing '{field}'")
        sid = step.get("id")
        if sid:
            if sid in step_ids:
                errors.append(f"Duplicate step id: {sid}")
            step_ids.add(sid)

    # Check blocked_by references
    for step in steps:
        for dep in step.get("blocked_by", []):
            if dep not in step_ids:
                errors.append(f"Step '{step.get('id')}' references unknown dependency: {dep}")

    return errors


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    exit_code = 0

    # Validate example manifests
    examples_dir = os.path.join(root, "examples")
    if os.path.isdir(examples_dir):
        for fname in sorted(os.listdir(examples_dir)):
            if fname.endswith(".json"):
                path = os.path.join(examples_dir, fname)
                errors = validate_manifest(path)
                if errors:
                    print(f"FAIL  {fname}")
                    for e in errors:
                        print(f"      {e}")
                    exit_code = 1
                else:
                    print(f"PASS  {fname}")

    # Validate sample plan
    plan_path = os.path.join(root, "tests", "sample-plan.json")
    if os.path.isfile(plan_path):
        errors = validate_plan(plan_path)
        if errors:
            print(f"FAIL  tests/sample-plan.json")
            for e in errors:
                print(f"      {e}")
            exit_code = 1
        else:
            print(f"PASS  tests/sample-plan.json")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
