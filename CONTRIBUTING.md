# Contributing to AutoCode

Thanks for your interest in contributing. AutoCode is a set of markdown skill files for Claude Code — no build step, no compiled code, no runtime dependencies.

## Project Structure

```
commands/   → Claude Code slash commands (user-invokable via /command-name)
agents/     → Agent role definitions (spawned by the orchestrator)
schemas/    → JSON schema for autocode.manifest.json
examples/   → Example manifests for different project types
docs/       → Documentation
tests/      → Test suite
```

## How to Contribute

### Fixing a bug or improving a command

1. Fork the repo
2. Edit the relevant `.md` file in `commands/` or `agents/`
3. Run `./test.sh` to verify nothing broke
4. Open a PR

### Adding a new example manifest

1. Create a new `.json` file in `examples/`
2. Include all top-level sections (use an existing example as a template)
3. Run `./test.sh` — it validates all examples automatically

### Improving documentation

Edit files in `docs/` or `README.md`. The test suite checks that cross-references and links are valid.

## Conventions

- **Commands** (`commands/*.md`) must have a `## Steps`, `## Usage`, `## Behavior`, or `## Output Format` section
- **Agents** (`agents/*.md`) should have structured sections (`## Constraints`, `## Input`, `## Output`, `## Time Budget`)
- **Examples** (`examples/*.json`) must include all sections defined in the schema
- All commands start with a branded header (see any existing command for the format)
- Use consistent status indicators: `✓` success, `✗` failure, `○` pending, `►` in-progress

## Testing

Run the test suite before submitting:

```bash
./test.sh
```

This validates JSON files, schema structure, agent/command conventions, cross-references, and link integrity. All 54+ checks must pass.

## What NOT to change

- `schemas/manifest.schema.json` changes require updating all 4 examples
- Don't add runtime dependencies — AutoCode is pure skill files
- Don't add hashtags to any marketing copy
