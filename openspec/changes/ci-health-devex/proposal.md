## Why

CI is slow (3 parallel jobs each repeating full nix+npm setup), pi tests exist but are never run, there are no contract tests for agent JSON formats, and the flake is unpinned (`--no-write-lock-file`). Agents and humans both need fast, deterministic feedback loops — right now the pipeline gives neither speed nor confidence.

## What Changes

- Consolidate 3 CI jobs (lint, test, e2e) into a single job to eliminate redundant nix evaluation and npm installs
- Add concurrency control to cancel stale CI runs on the same branch
- Wire up pi tests (add test script to package.json, add `test:pi` to Taskfile, include in CI)
- Pin the nix flake lock (commit `flake.lock`, remove `--no-write-lock-file`)
- Add agent JSON contract test fixtures (snapshot real payloads from each agent)
- Add a local `task check` pre-push hook script for instant feedback
- Add CI status badge to README

## Capabilities

### New Capabilities
- `ci-consolidation`: Single CI job with sequential lint/test/e2e steps, concurrency groups, and cached nix evaluation
- `agent-contract-tests`: Fixture-based contract tests that snapshot real agent JSON payloads and verify parsers against them
- `local-checks`: Pre-push hook and `task check` improvements for fast local feedback

### Modified Capabilities

## Impact

- `.github/workflows/ci.yml` — rewritten to single job
- `tools/Taskfile.yml` — add `test:pi` task
- `tools/pi/package.json` — add test script and vitest dep
- `Taskfile.yml` — update `test` to include pi, improve `check` target
- `flake.nix` / `flake.lock` — pin the lock file
- `tools/neph-cli/tests/` — add contract fixture files and tests
- `.githooks/pre-push` — new hook script
- `README.md` — add CI badge
