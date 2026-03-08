## 1. Agent Definition Breaking Changes

- [x] 1.1 Update all 10 agent definitions: replace `integration = { type = "...", ... }` with flat `type = "extension"|"hook"` field, remove `send_adapter` from pi
- [x] 1.2 Update `contracts.lua`: remove `send_adapter` and `integration` from optional fields, add `type` with validation (must be "extension" or "hook" if present), add helpful errors for removed fields
- [x] 1.3 Update agent submodule tests and contract tests to match new schema

## 2. Bus Module (Lua)

- [x] 2.1 Create `lua/neph/internal/bus.lua` with `register(params)`, `send_prompt(name, text, opts)`, `is_connected(name)`, `unregister(name)`, and health-check timer
- [x] 2.2 Add `bus.register` dispatch entry to `rpc.lua`
- [x] 2.3 Add bus tests (register, send_prompt connected/unconnected, unregister, invalid agent rejection)

## 3. Session Send Routing

- [x] 3.1 Update `session.lua` send path: check `agent.type == "extension"` and route through bus if connected, fall through to terminal if not
- [x] 3.2 Remove `send_adapter` dispatch logic and `neph_pending_prompt` cleanup from session.lua
- [x] 3.3 Update session.lua open/kill_session: replace `agent.integration` checks with `agent.type` checks
- [x] 3.4 Update debug logging in session.lua send to reflect bus routing instead of adapter routing

## 4. TypeScript Client SDK

- [x] 4.1 Create `tools/lib/neph-client.ts` with NephClient class: connect, register, onPrompt, setStatus, unsetStatus, review, checktime, disconnect, auto-reconnect
- [x] 4.2 Add Vitest tests for NephClient (mock socket connection, verify register call, verify notification handling)

## 5. Pi Extension Rewrite

- [x] 5.1 Rewrite `tools/pi/pi.ts` to use NephClient: replace polling loop and fire-and-forget queue with persistent connection and notification listener
- [x] 5.2 Update pi.ts tests to reflect new connection model

## 6. Cleanup

- [x] 6.1 Remove `neph_pending_prompt` references from debug-logging spec and codebase (log.lua pi adapter messages, pi send_adapter tests in agent_submodules_spec)
- [x] 6.2 Update AGENTS.md documentation to reflect new `type` field and removed `send_adapter`/`integration`
