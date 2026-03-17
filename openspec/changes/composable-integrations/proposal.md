## Why

Neph’s current integration paths are tightly coupled to specific harnesses and Neovim-side tooling, which makes it brittle as agent ecosystems change (e.g., Cupcake harness gaps) and makes it hard to mix policy engines, review UX, and agent hooks. We need a composable integration pipeline with group defaults so each agent can plug into the same canonical flow without duplicating logic or re-implementing policy/review behavior.

## What Changes

- Introduce a canonical integration pipeline (adapter → policy engine → review provider → response formatter) with explicit interfaces and swappable components.
- Add group defaults to define dependency trees (policy engine, review provider, formatter) for sets of agents, with per-agent overrides.
- Move integration install/validation to the neph CLI, with `neph integration` and `neph deps` commands for toggling, status, and configuration inspection.
- Make the Neovim diff-hunk review provider an explicit opt-in registration; default review provider is `noop` (writes proceed normally).
- **BREAKING**: Deprecate Neovim-side `:NephTools` install flow in favor of CLI-managed integration.

## Capabilities

### New Capabilities
- `integration-pipeline`: Canonical event/decision flow with pluggable adapter, policy engine, review provider, and formatter.
- `integration-groups`: Group defaults that define dependency trees for agent families with per-agent overrides.
- `integration-cli`: CLI commands for integration install/validation/status and config inspection (`neph integration`, `neph deps`).
- `review-provider-optin`: Explicit registration of the Neovim diff-hunk review provider with a `noop` default.

### Modified Capabilities
- `neph-cli`: Adds integration/deps commands and canonical decision plumbing.
- `tool-install`: Moves integration install/validation to CLI and away from Neovim startup.
- `tools-commands`: Deprecates or removes Neovim `:NephTools` as the primary installer.
- `tools-checkhealth`: Health checks rely on CLI integration status instead of Neovim-managed installs.

## Impact

- Neovim plugin: `lua/neph/init.lua`, `lua/neph/config.lua`, `lua/neph/health.lua`, `lua/neph/tools.lua` (review provider opt-in, health/status changes, tool install removal).
- CLI tooling: `tools/neph-cli/` gains integration/deps commands and status reporting.
- Agent integrations: hook configs and adapters for Amp, Gemini, Pi, and harness-backed agents.
- Docs/tests: new specs for integration pipeline, CLI, and review provider; updates to install and health docs/tests.
