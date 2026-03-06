# Testing Strategy

Neph.nvim uses a multi-layered testing strategy to ensure reliability across its Lua, TypeScript, and RPC components.

## 1. Lua Unit Tests (Neovim Headless)

Located in `tests/api/review/`.
Run using `plenary.busted`.

**What they cover:**
- **Review Engine** (`engine_spec.lua`): Pure logic for hunk computation, applying decisions, and building envelopes.
- **RPC Dispatch** (`contract_spec.lua`): Ensures the dispatch facade matches `protocol.json`.

**Command:**
```bash
task test:lua
```

## 2. CLI Unit Tests (Node/Vitest)

Located in `tools/neph-cli/tests/`.
Run using `vitest`.

**What they cover:**
- **Command Handling** (`commands.test.ts`): Tests CLI argument parsing and `FakeTransport` calls.
- **Transport Injection**: Verifies that the CLI's Neovim RPC client correctly formats msgpack requests.

**Command:**
```bash
task tools:test:neph
```

## 3. Contract Tests (Lua & TS)

Located in both `tests/` and `tools/neph-cli/tests/`.
These tests validate that both the Lua API and the TypeScript CLI are in sync with the canonical `protocol.json` contract.

## 4. Pi Extension Tests (Node/Vitest)

Located in `tools/pi/tests/`.
Verifies that the `pi` agent extension correctly spawns `neph` as a subprocess and handles its output.

**Command:**
```bash
task tools:test:pi
```

## 5. Manual UI Verification

Since Neovim UI components (signs, virtual text, `Snacks.picker`) are difficult to test headlessly, they require manual verification.

**Verification Flow:**
1. Open Neovim.
2. Trigger an agent turn that performs a `write` or `edit` tool call.
3. Verify that the diff tab opens correctly.
4. Verify that per-hunk decisions (`Accept`, `Reject`, etc.) update signs and virtual text accurately.
5. Verify that `Accept all` and `Reject all` behave as expected.

## 6. Continuous Integration (Dagger)

The full suite is executed in a Dagger pipeline defined in `.fluentci/ci.ts`.
The pipeline uses `nix develop` to provide a deterministic test environment (Neovim, Node, Plenary, etc.) defined in `flake.nix`.
