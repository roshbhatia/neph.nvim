## Why

neph.nvim hardcodes 10 agent definitions in `agents.lua` and resolves backends via an if/elseif chain in `session.lua`. Adding a new agent or backend means editing core files. The `enabled_agents` allowlist and `multiplexer` string enum are workarounds for the fact that the core owns all the definitions. This change replaces those patterns with constructor injection — users pass agent definitions and backend modules directly into `setup()`, and the core validates and uses what it's given.

## What Changes

- **BREAKING**: `agents` config key changes from `neph.AgentDef[]` (merge overrides) to the **sole source** of agent definitions. No built-in agents exist in core; all definitions move to `lua/neph/agents/*.lua` submodules.
- **BREAKING**: `multiplexer` string enum (`"snacks"|"wezterm"|"tmux"|"zellij"`) replaced by `backend` key accepting a backend module table directly. `require("neph.backends.snacks")` replaces `multiplexer = "snacks"`.
- **BREAKING**: `enabled_agents` config key removed. Unnecessary when agents are explicitly injected.
- Add `lua/neph/agents/` directory with one file per agent (claude, goose, opencode, amp, copilot, gemini, codex, crush, cursor, pi), each returning an `AgentDef` table.
- Add `lua/neph/agents/all.lua` convenience re-export returning all agent definitions.
- Move `lua/neph/internal/backends/` to `lua/neph/backends/` (peer to `agents/`).
- Add `lua/neph/internal/contracts.lua` with `validate_agent()` and `validate_backend()` functions that assert required fields/methods at setup time.
- Remove `agents.merge()` — no longer needed when agents are injected.
- `session.lua` receives its backend reference from `setup()` args instead of resolving via string lookup.

## Capabilities

### New Capabilities
- `constructor-injection`: Contract validation and dependency injection wiring in `setup()` — agents and backend are passed in, validated, stored.
- `agent-submodules`: Agent definitions as standalone Lua modules under `neph.agents.*`, each returning an `AgentDef` table.
- `backend-submodules`: Backend implementations as standalone Lua modules under `neph.backends.*`, each conforming to the validated backend interface.

### Modified Capabilities
- `config-module`: Config type changes — `multiplexer` replaced by `backend`, `enabled_agents` removed, `agents` semantics change from merge-override to sole source.
- `selective-install`: No longer a string allowlist; agents are selected by which submodules you `require()` into the `agents` array.
- `multiplexer-config`: Replaced entirely by direct backend injection via the `backend` config key.
- `send-adapters`: No behavioral change, but the adapter is now carried on the injected AgentDef rather than looked up from the internal registry.

## Impact

- **Public API**: `require("neph").setup()` signature changes — all existing configs using `multiplexer` or `enabled_agents` must update.
- **Agent registry**: `require("neph.internal.agents")` loses its hardcoded list and `merge()` function; becomes a thin wrapper around the injected array.
- **Backend resolution**: `session.lua` no longer requires backend modules by string — it uses the injected module reference.
- **Directory structure**: `lua/neph/agents/` and `lua/neph/backends/` become new top-level module directories alongside `internal/` and `api/`.
- **Tests**: Agent and config tests need updating for new injection pattern.
- **No external dependency changes**: snacks.nvim remains the only mandatory runtime dep (when using the snacks backend).
