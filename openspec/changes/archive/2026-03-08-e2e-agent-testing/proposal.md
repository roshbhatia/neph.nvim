## Why

The pi crash bug (pi exits immediately and quits neovim) was only discovered by manual testing after deployment. No automated test verifies that agent integrations actually work end-to-end — unit tests mock `spawn` and can't catch runtime bundling issues, process lifecycle timing bugs, or extension loading failures. We need automated e2e tests that launch real agents in a headless neovim and verify they don't crash.

## What Changes

- Install agent binaries (pi, claude, copilot, gemini, amp, opencode) as dev/test dependencies
- Add a headless neovim e2e test harness that can launch the plugin and open agent terminals
- Create tiered e2e tests:
  - **Tier 1 (smoke)**: Plugin loads, `tools.install()` completes, symlinks/merges are correct
  - **Tier 2 (launch)**: Each agent opens in a terminal without crashing neovim, `vim.g.<agent>_active` is set, terminal closes cleanly
  - **Tier 3 (hook)**: Hook-based agents (claude, gemini) fire `neph gate` correctly on write tool calls
- Integrate e2e tests into the existing CI pipeline (FluentCI/Dagger)
- Add a `task test:e2e` target to the Taskfile

## Capabilities

### New Capabilities
- `e2e-test-harness`: Headless neovim test runner that can programmatically load neph.nvim, open agent terminals, assert on vim globals, and verify process lifecycle
- `agent-install`: Dev-time installation of agent binaries needed for e2e testing (pi, claude, etc.)
- `ci-e2e`: Integration of e2e tests into the FluentCI/Dagger CI pipeline

### Modified Capabilities

## Impact

- **New dev dependencies**: Agent CLI binaries (npm packages, cargo crate, etc.)
- **CI pipeline**: `.fluentci/ci.ts` gains an e2e test stage; CI container needs agent binaries
- **Taskfile**: New `test:e2e` task
- **New test files**: `tests/e2e/` directory with harness and per-agent test scripts
- **No runtime changes**: This is test infrastructure only — no changes to plugin code or user-facing behavior
