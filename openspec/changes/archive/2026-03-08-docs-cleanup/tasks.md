## 1. AGENTS.md — Code Organization & Overview

- [x] 1.1 Update Project Overview section — remove references to "agent backends" string enum, describe DI pattern
- [x] 1.2 Rewrite Code Organization tree — add `agents/`, `backends/`, `contracts.lua`; remove `internal/backends/`
- [x] 1.3 Update installation example to show `agents = { ... }, backend = ...` DI pattern

## 2. AGENTS.md — Critical Patterns

- [x] 2.1 Rewrite "Agent Registration" section — describe agent submodules at `lua/neph/agents/*.lua` returning `AgentDef` tables, not hardcoded list
- [x] 2.2 Rewrite "Multiplexer Backends" section → rename to "Backend Modules", describe `lua/neph/backends/*.lua` with DI, remove tmux/zellij stubs
- [x] 2.3 Update "Adding a New Agent" guide — create submodule file, add to `all.lua`, pass in `setup()`
- [x] 2.4 Update "Adding a New Backend" guide — create module at `lua/neph/backends/`, implement interface, pass in `setup()`

## 3. AGENTS.md — Gotchas & Miscellany

- [x] 3.1 Remove gotcha about `full_cmd` LSP warnings (no longer relevant)
- [x] 3.2 Remove/rewrite Snacks.nvim gotcha — fix path from `internal/backends/snacks.lua` to `backends/snacks.lua`
- [x] 3.3 Add gotcha about contract validation — setup() fails loud if agent/backend doesn't conform
- [x] 3.4 Update "Agent Terminal State" gotcha — session.lua now receives backend via DI, not detect_backend()
- [x] 3.5 Remove "Multi-Protocol Architecture (Planned)" section — references nonexistent openspec change
- [x] 3.6 Update Last Updated date

## 4. docs/testing.md

- [x] 4.1 Rewrite to list all current test suites: contracts_spec, agent_submodules_spec, backend_conformance_spec, setup_smoke_spec, agents_spec, config_spec, session_spec, placeholders_spec, context_spec, history_spec, review engine_spec, contract_spec (Lua + TS), pi tests
- [x] 4.2 Verify test commands match current Taskfile

## 5. docs/rpc-protocol.md

- [x] 5.1 Verify method list against current protocol.json — update if any methods missing or extra

## 6. Module Docstrings

- [x] 6.1 Audit and update `@mod`/`@brief` annotations in `agents.lua`, `session.lua`, `tools.lua` — remove references to old patterns
