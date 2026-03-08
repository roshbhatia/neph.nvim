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
| `placeholders_spec.lua` | Placeholder token expansion (+file, +cursor, etc.) |
| `context_spec.lua` | Editor context capture helpers |
| `history_spec.lua` | Per-agent prompt history ring buffer |
| `contract_spec.lua` | Lua RPC dispatch matches `protocol.json` |
| `rpc_spec.lua` | RPC dispatch facade routing |
| `api/review/engine_spec.lua` | Hunk computation, decision application, envelope building |
| `api/buffers_spec.lua` | Buffer/tab operations |
| `api/status_spec.lua` | vim.g status management |

## 2. CLI Unit Tests (Node/Vitest)

Located in `tools/neph-cli/tests/`. Run using `vitest`.

**What they cover:**
- **Command Handling** (`commands.test.ts`): Tests CLI argument parsing and `FakeTransport` calls.
- **Contract Validation** (`contract.test.ts`): Validates CLI matches `protocol.json`.
- **RPC Integration** (`integration/rpc.test.ts`): RPC round-trip tests.

**Command:**
```bash
task tools:test:neph
```

## 3. Contract Tests (Lua & TS)

Located in both `tests/` and `tools/neph-cli/tests/`.
These tests validate that both the Lua RPC dispatch and the TypeScript CLI are in sync with the canonical `protocol.json` contract.

**When adding a new RPC method, update:**
1. `protocol.json` — Add method definition
2. `lua/neph/rpc.lua` — Add dispatch handler
3. `tests/contract_spec.lua` — Add to expected methods
4. `tools/neph-cli/tests/contract.test.ts` — Add to expected methods

## 4. Pi Extension Tests (Node/Vitest)

Located in `tools/pi/tests/`.
Verifies that the `pi` agent extension correctly spawns `neph` as a subprocess and handles its output.

**Command:**
```bash
task tools:test:pi
```

## 5. E2E Tests

Located in `tests/e2e/`. Runs headless Neovim smoke tests and agent launch verification.

**Command:**
```bash
task test:e2e
```

## 6. Manual UI Verification

Since Neovim UI components (signs, virtual text, `Snacks.picker`) are difficult to test headlessly, they require manual verification.

**Verification Flow:**
1. Open Neovim.
2. Trigger an agent turn that performs a `write` or `edit` tool call.
3. Verify that the diff tab opens correctly.
4. Verify that per-hunk decisions (`Accept`, `Reject`, etc.) update signs and virtual text accurately.
5. Verify that `Accept all` and `Reject all` behave as expected.

## 7. Continuous Integration (Dagger)

The full suite is executed in a Dagger pipeline defined in `.fluentci/ci.ts`.
The pipeline uses `nix develop` to provide a deterministic test environment (Neovim, Node, Plenary, etc.) defined in `flake.nix`.

**Run CI locally:**
```bash
task ci
```
