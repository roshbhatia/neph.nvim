# Testing Strategy

Neph.nvim uses a multi-layered testing strategy to ensure reliability across its Lua, TypeScript, and RPC components.

## 1. Lua Unit Tests (Neovim Headless)

Located in `tests/`. Run using `plenary.busted`.

**Command:**
```bash
task test
```

### Test Suites

| File | Description |
|------|-------------|
| `contracts_spec.lua` | Contract validation: validate_agent, validate_backend, validate_tools |
| `agent_submodules_spec.lua` | Every agent submodule (`lua/neph/agents/*.lua`) passes validation |
| `backend_conformance_spec.lua` | Snacks and WezTerm backends pass validate_backend |
| `setup_smoke_spec.lua` | Full DI wiring: setup with stub backend, real agents, negative paths |
| `agents_spec.lua` | Agent accessor: init/get_all/get_by_name, executable filtering |
| `config_spec.lua` | Config defaults, no removed fields (multiplexer, enabled_agents) |
| `session_spec.lua` | Session management with stub backend injection |
| `placeholders_spec.lua` | Placeholder token expansion (+file, +cursor, +selection, etc.) |
| `context_spec.lua` | Editor context capture helpers |
| `history_spec.lua` | Per-agent prompt history ring buffer |
| `contract_spec.lua` | Lua RPC dispatch matches `protocol.json` |
| `rpc_spec.lua` | RPC dispatch facade routing |
| `api/review/engine_spec.lua` | Hunk computation, decision application, envelope building |
| `api/buffers_spec.lua` | Buffer/tab operations |
| `api/status_spec.lua` | vim.g status management |

## 2. CLI Unit Tests (Node/Vitest)

Located in `tools/neph-cli/tests/`. Run using `vitest`.

**Command:**
```bash
task tools:test:neph
```

### Test Suites

| File | Description |
|------|-------------|
| `commands.test.ts` | CLI argument parsing and FakeTransport calls |
| `contract.test.ts` | Validates CLI matches `protocol.json` |
| `gate.test.ts` | Gate parsers for all agents (Claude, Copilot, Gemini, Cursor) |
| `gate.contract.test.ts` | Gate schema contract validation |
| `gate.fuzz.test.ts` | Fuzz testing for gate parsers (124 test cases) |
| `hook-configs.test.ts` | Hook configuration generation for agents |
| `transport.test.ts` | Transport layer tests |
| `integration/rpc.test.ts` | RPC round-trip tests |

## 3. Shared Library Tests (Node/Vitest)

Located in `tools/lib/tests/`. Run as part of `task tools:test:neph`.

| File | Description |
|------|-------------|
| `log.test.ts` | Debug logger tests |

## 4. Pi Extension Tests (Node/Vitest)

Located in `tools/pi/tests/`. Verifies that the Pi Cupcake harness correctly intercepts write/edit tool_call events.

**Command:**
```bash
task tools:test:pi
```

| File | Description |
|------|-------------|
| `pi.test.ts` | Extension lifecycle, tool registration, review flow, status updates (21 tests) |

## 5. Contract Tests (Lua & TS)

Located in both `tests/` and `tools/neph-cli/tests/`.
These tests validate that both the Lua RPC dispatch and the TypeScript CLI are in sync with the canonical `protocol.json` contract.

**When adding a new RPC method, update:**
1. `protocol.json` — Add method definition
2. `lua/neph/rpc.lua` — Add dispatch handler
3. `tests/contract_spec.lua` — Add to expected methods
4. `tools/neph-cli/tests/contract.test.ts` — Add to expected methods

## 6. E2E Tests

Located in `tests/e2e/`. Runs headless Neovim smoke tests and agent launch verification.

**Command:**
```bash
task test:e2e
```

## 7. Manual UI Verification

Since Neovim UI components (vimdiff tabs, signs, virtual text, winbar) are difficult to test headlessly, they require manual verification.

**Verification Flow:**
1. Open Neovim.
2. Trigger an agent turn that performs a `write` or `edit` tool call.
3. Verify that the vimdiff tab opens with current (left) and proposed (right) panes.
4. Verify per-hunk decisions (`ga`=accept, `gr`=reject) update signs and winbar.
5. Verify `gA` (accept all) and `gR` (reject all) behave as expected.
6. Verify line numbers are visible and dropbar doesn't obscure the winbar labels.

## 8. Continuous Integration (Dagger)

The full suite is executed in a Dagger pipeline defined in `.fluentci/ci.ts`.
The pipeline uses `nix develop` to provide a deterministic test environment (Neovim, Node, Plenary, etc.) defined in `flake.nix`.

**Run CI locally:**
```bash
task ci
```
