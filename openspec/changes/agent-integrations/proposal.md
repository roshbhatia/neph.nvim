## Why

Neph registers 10 agents but only pi has a deep integration — overriding write/edit tools so every file mutation goes through `neph review`. The remaining agents run as bare terminal processes with no review gating and no deterministic file-write control. Most modern agent CLIs now support hooks or tool overrides that can intercept file writes. We should use these mechanisms to enforce that every capable agent's file writes go through `neph review`.

The integration must be composable (shared building blocks, not per-agent monoliths), testable without neovim, and zero-overhead for users (single binary already on PATH).

## What Changes

- **New**: `neph gate` subcommand — reads agent hook stdin JSON, normalizes to file_path + content, runs the existing review flow internally, exits 0 (accept) or 2 (reject). Also manages `vim.g` state for passive autoattach. No separate shell script, no jq dependency.
- **New**: `tools/lib/neph-run.ts` — shared TypeScript module extracted from pi.ts containing `nephRun()`, `review()`, and fire-and-forget `neph()` helpers. Used by pi, amp, and opencode adapters.
- **New**: Hook configs for shell-hook agents (claude, copilot, cursor, gemini) — JSON files pointing to `neph gate --agent <name>`
- **New**: TypeScript adapters for plugin-API agents (amp, opencode) — thin wrappers importing from `lib/neph-run.ts`
- **New**: `integration` field on agent definitions in `agents.lua` — declares `type` (hook/extension/nil) and `capabilities` per agent
- **New**: session.lua uses capability metadata to manage `vim.g` state for terminal-only agents, defer to hooks/extensions for others
- **New**: Comprehensive vitest suite for gate command, lib module, adapters, and hook config validation — all without neovim
- **Updated**: CI hardening — ensure `task ci` and `task dagger` pass locally and remotely
- **Preserve**: Existing pi integration unchanged (refactored to import from `lib/neph-run.ts`)
- **Not supported**: Goose (no hooks), Codex (no write interception), Crush (no docs) — terminal-only

## Capabilities

### New Capabilities

- `neph-gate-command`: A new `neph gate` subcommand that serves as the universal hook handler for shell-hook agents. Reads tool input JSON from stdin, normalizes across agent formats, runs review internally, manages `vim.g` state, returns exit codes.
- `shared-neph-run`: Shared TypeScript module (`tools/lib/neph-run.ts`) extracted from pi.ts — `nephRun()`, `review()`, fire-and-forget `neph()`. Used by all TypeScript agent adapters.
- `agent-hook-configs`: Per-agent JSON hook configuration files for claude, copilot, cursor, and gemini — each points to `neph gate --agent <name>`.
- `agent-ts-adapters`: TypeScript plugin/tool adapters for amp and opencode — thin wrappers using `lib/neph-run.ts`.
- `agent-capability-metadata`: `integration` field on agent definitions declaring type and capabilities, driving session.lua behavior.
- `agent-integration-tests`: Vitest suite validating gate command, lib module, adapters, hook config syntax, and protocol contract — all without neovim.
- `ci-hardening`: Ensure full CI pipeline runs reliably locally and remotely.

### Modified Capabilities

- `tool-install`: Extend `tools.lua` to install hook configs to agent-specific locations.

## Impact

**Code Changes:**
- New: `neph gate` command in `tools/neph-cli/src/index.ts`
- New: `tools/lib/neph-run.ts` (extracted from pi.ts)
- New: `tools/claude/settings.json`, `tools/copilot/hooks.json`, `tools/cursor/hooks.json`, `tools/gemini/settings.json`
- New: `tools/amp/neph-plugin.ts`, `tools/opencode/neph-write.ts`
- New: vitest tests for gate, lib, adapters, config validation
- Updated: `tools/pi/pi.ts` — refactored to import from `lib/neph-run.ts`
- Updated: `lua/neph/internal/agents.lua` — integration metadata
- Updated: `lua/neph/internal/session.lua` — capability-driven state management
- Updated: `lua/neph/tools.lua` — install entries for hook configs
- Updated: `tools/neph-cli/src/index.ts` — gate subcommand
- Updated: `tools/Taskfile.yml` — test/lint tasks for new code

**Dependencies:**
- No new runtime dependencies (neph CLI is already on PATH)
- No jq dependency (Node parses JSON natively)

**Risk:**
- Agent hook APIs may change upstream — configs are simple JSON, easy to update
- pi refactor to use shared lib must not change behavior
- Gate command stdin format normalization must handle all agent variations
