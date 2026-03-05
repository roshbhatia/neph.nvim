## 1. Review Engine (Pure Lua Logic)

- [ ] 1.1 Create `lua/neph/api/review/engine.lua` with hunk computation using `vim.diff()`
- [ ] 1.2 Implement `compute_hunks(old_lines, new_lines)` returning hunk ranges
- [ ] 1.3 Implement `apply_decisions(old_lines, new_lines, decisions)` returning final content
- [ ] 1.4 Implement `build_envelope(decisions, content)` returning ReviewEnvelope table
- [ ] 1.5 Implement state machine: `create_session()`, `accept()`, `reject(reason)`, `accept_all()`, `reject_all(reason)`
- [ ] 1.6 Create `tests/api/review/engine_spec.lua` — table-driven tests for hunk computation
- [ ] 1.7 Test envelope construction for accept, reject, partial decisions
- [ ] 1.8 Test state machine transitions and edge cases (no hunks, single hunk, all-accept, all-reject)

## 2. Review UI (Thin Adapter)

- [ ] 2.1 Create `lua/neph/api/review/ui.lua` extracting vimdiff + signs + picker from `open_diff.lua`
- [ ] 2.2 Wire UI to call engine for state transitions instead of inline logic
- [ ] 2.3 Wire UI to call engine for envelope construction on finalize
- [ ] 2.4 Implement atomic result write: write `.tmp`, `os.rename()` to final path
- [ ] 2.5 Add request_id to rpcnotify payload
- [ ] 2.6 Manual QA: verify existing review flow (accept, reject, partial, manual close) works unchanged

## 3. Lua API Modules

- [ ] 3.1 Create `lua/neph/api/status.lua` with `set(params)` and `unset(params)`
- [ ] 3.2 Create `lua/neph/api/buffers.lua` with `checktime(params)` and `close_tab(params)`
- [ ] 3.3 Create `lua/neph/api/review/init.lua` with `open(params)` wiring engine + UI
- [ ] 3.4 Create `tests/api/status_spec.lua` — verify vim.g set/unset
- [ ] 3.5 Create `tests/api/buffers_spec.lua` — verify checktime/close_tab behavior

## 4. RPC Dispatch Facade

- [ ] 4.1 Create `lua/neph/rpc.lua` with dispatch table and `request(method, params)`
- [ ] 4.2 Implement error normalization: `{ ok, result }` / `{ ok, error = { code, message } }`
- [ ] 4.3 Create `tests/rpc_spec.lua` — test dispatch routing, unknown method error, pcall error handling
- [ ] 4.4 Create `protocol.json` with method catalog and version

## 5. neph CLI — Core

- [ ] 5.1 Create `tools/neph-cli/` directory with `package.json`, `tsconfig.json`, `vitest.config.ts`
- [ ] 5.2 Define `NvimTransport` interface: `executeLua()`, `onNotification()`, `close()`
- [ ] 5.3 Implement `SocketTransport` wrapping `@neovim/node-client` over Unix socket
- [ ] 5.4 Implement socket auto-discovery (port from shim.py `discover_nvim_socket`)
- [ ] 5.5 Implement CLI entry point with subcommands: `review`, `set`, `unset`, `checktime`, `close-tab`, `status`, `spec`
- [ ] 5.6 All commands use single Lua string: `return require("neph.rpc").request(...)`
- [ ] 5.7 `neph spec` outputs tool schema JSON for PATH agent discovery
- [ ] 5.8 Dry-run mode: `NEPH_DRY_RUN=1` or no socket → auto-accept for review
- [ ] 5.9 Add esbuild config for single-file bundle

## 6. neph CLI — Review Protocol

- [ ] 6.1 Generate request_id (uuid) per review invocation
- [ ] 6.2 Create result_path temp file, pass to Lua with request_id and channel_id
- [ ] 6.3 Subscribe to `neph:review_done` notification, filter by request_id
- [ ] 6.4 On notification: read result file, parse JSON, print to stdout, cleanup, exit
- [ ] 6.5 Add file-watch fallback (`fs.watch`) in case notification is dropped
- [ ] 6.6 Add timeout (300s) with clean error envelope on expiry

## 7. neph CLI — Tests

- [ ] 7.1 Create `FakeTransport` implementing `NvimTransport` — records calls, returns scripted responses
- [ ] 7.2 Create `tests/commands.test.ts` — test each command's transport calls and stdout output
- [ ] 7.3 Test review command: request_id generation, notification handling, envelope output
- [ ] 7.4 Test dry-run/offline path: auto-accept without transport
- [ ] 7.5 Test error cases: transport failure, timeout, malformed response
- [ ] 7.6 Create `tests/integration/rpc.test.ts` — spawn headless nvim, test end-to-end review
- [ ] 7.7 Integration test: verify `neph status` connects and returns JSON
- [ ] 7.8 Integration test: verify `neph set`/`unset` modifies vim.g

## 8. Contract Tests

- [ ] 8.1 Create `tests/contract_spec.lua` — load `protocol.json`, assert every method exists in `rpc.lua` dispatch
- [ ] 8.2 Create `tests/contract.test.ts` — load `protocol.json`, assert every CLI command references a known method
- [ ] 8.3 Validate protocol version field matches between Lua and TS

## 9. Pi Adapter Refactor

- [ ] 9.1 Refactor `tools/pi/pi.ts` — replace `shimRun`/`shimQueue` with `neph` CLI spawn
- [ ] 9.2 Remove all inline Lua strings and shim-specific logic from pi.ts
- [ ] 9.3 Update `tools/pi/tests/pi.test.ts` — mock `neph` spawn instead of `shim` spawn
- [ ] 9.4 Verify existing test scenarios pass with new CLI contract
- [ ] 9.5 Update `tools.lua` — symlink `neph` CLI instead of `shim.py`

## 10. CI Pipeline Migration

- [ ] 10.1 Update `.fluentci/ci.ts` — use `nix develop --no-write-lock-file -c` instead of `nix-shell`
- [ ] 10.2 Add `NIX_CONFIG="experimental-features = nix-command flakes"` to container env
- [ ] 10.3 Add `npm ci` step for `tools/neph-cli/` in Dagger pipeline
- [ ] 10.4 Update `Taskfile.yml` — add `test:cli` target for neph-cli vitest
- [ ] 10.5 Update `tools/Taskfile.yml` — replace `test:core` (pytest) with `test:neph` (vitest)
- [ ] 10.6 Update `tools/Taskfile.yml` — replace `lint:core` (flake8) with `lint:neph` (eslint or deno lint)
- [ ] 10.7 Verify full `task ci` passes in Dagger locally before any push

## 11. Cleanup

- [ ] 11.1 Delete `tools/core/shim.py`
- [ ] 11.2 Delete `tools/core/lua/` (open.lua, open_diff.lua, revert.lua)
- [ ] 11.3 Delete `tools/core/tests/` (Python test infrastructure)
- [ ] 11.4 Delete `tools/core/pyproject.toml`, `tools/core/uv.lock`
- [ ] 11.5 Remove Python/flake8 from `flake.nix` devShell buildInputs
- [ ] 11.6 Remove `uv` from `flake.nix` devShell buildInputs

## 12. Documentation

- [ ] 12.1 Add `mini.doc` to `flake.nix` devShell
- [ ] 12.2 Add EmmyLua annotations to all new `lua/neph/api/` modules
- [ ] 12.3 Create `scripts/docgen.lua` — generate `doc/neph.txt` via mini.doc
- [ ] 12.4 Add `task docs` target to Taskfile.yml
- [ ] 12.5 Write `docs/architecture.md` — module boundaries, data flow diagram
- [ ] 12.6 Write `docs/rpc-protocol.md` — method catalog, payload shapes, versioning
- [ ] 12.7 Write `docs/testing.md` — test structure, how to run, CI pipeline
- [ ] 12.8 Update `README.md` — updated architecture overview, installation, agent configuration
