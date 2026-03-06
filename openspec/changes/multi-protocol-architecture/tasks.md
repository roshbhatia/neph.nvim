## 1. Review Engine (Pure Lua Logic)

- [x] 1.1 Create `lua/neph/api/review/engine.lua` with hunk computation using `vim.diff()`
- [x] 1.2 Implement `compute_hunks(old_lines, new_lines)` returning hunk ranges
- [x] 1.3 Implement `apply_decisions(old_lines, new_lines, decisions)` returning final content
- [x] 1.4 Implement `build_envelope(decisions, content)` returning ReviewEnvelope table
- [x] 1.5 Implement state machine: `create_session()`, `accept()`, `reject(reason)`, `accept_all()`, `reject_all(reason)`
- [x] 1.6 Create `tests/api/review/engine_spec.lua` — table-driven tests for hunk computation
- [x] 1.7 Test envelope construction for accept, reject, partial decisions
- [x] 1.8 Test state machine transitions and edge cases (no hunks, single hunk, all-accept, all-reject)

## 2. Review UI (Thin Adapter)

- [x] 2.1 Create `lua/neph/api/review/ui.lua` extracting vimdiff + signs + picker from `open_diff.lua`
- [x] 2.2 Wire UI to call engine for state transitions instead of inline logic
- [x] 2.3 Wire UI to call engine for envelope construction on finalize
- [x] 2.4 Implement atomic result write: write `.tmp`, `os.rename()` to final path
- [x] 2.5 Add request_id to rpcnotify payload
- [ ] 2.6 Manual QA: verify existing review flow (accept, reject, partial, manual close) works unchanged

## 3. Lua API Modules

- [x] 3.1 Create `lua/neph/api/status.lua` with `set(params)` and `unset(params)`
- [x] 3.2 Create `lua/neph/api/buffers.lua` with `checktime(params)` and `close_tab(params)`
- [x] 3.3 Create `lua/neph/api/review/init.lua` with `open(params)` wiring engine + UI
- [x] 3.4 Create `tests/api/status_spec.lua` — verify vim.g set/unset
- [x] 3.5 Create `tests/api/buffers_spec.lua` — verify checktime/close_tab behavior

## 4. RPC Dispatch Facade

- [x] 4.1 Create `lua/neph/rpc.lua` with dispatch table and `request(method, params)`
- [x] 4.2 Implement error normalization: `{ ok, result }` / `{ ok, error = { code, message } }`
- [x] 4.3 Create `tests/rpc_spec.lua` — test dispatch routing, unknown method error, pcall error handling
- [x] 4.4 Create `protocol.json` with method catalog and version

## 5. neph CLI — Core

- [x] 5.1 Create `tools/neph-cli/` directory with `package.json`, `tsconfig.json`, `vitest.config.ts`
- [x] 5.2 Define `NvimTransport` interface: `executeLua()`, `onNotification()`, `close()`
- [x] 5.3 Implement `SocketTransport` wrapping `@neovim/node-client` over Unix socket
- [x] 5.4 Implement socket auto-discovery (port from shim.py `discover_nvim_socket`)
- [x] 5.5 Implement CLI entry point with subcommands: `review`, `set`, `unset`, `checktime`, `close-tab`, `status`, `spec`
- [x] 5.6 All commands use single Lua string: `return require("neph.rpc").request(...)`
- [x] 5.7 `neph spec` outputs tool schema JSON for PATH agent discovery
- [x] 5.8 Dry-run mode: `NEPH_DRY_RUN=1` or no socket → auto-accept for review
- [x] 5.9 Add esbuild config for single-file bundle

## 6. neph CLI — Review Protocol

- [x] 6.1 Generate request_id (uuid) per review invocation
- [x] 6.2 Create result_path temp file, pass to Lua with request_id and channel_id
- [x] 6.3 Subscribe to `neph:review_done` notification, filter by request_id
- [x] 6.4 On notification: read result file, parse JSON, print to stdout, cleanup, exit
- [x] 6.5 Add file-watch fallback (`fs.watch`) in case notification is dropped
- [x] 6.6 Add timeout (300s) with clean error envelope on expiry

## 7. neph CLI — Tests

- [x] 7.1 Create `FakeTransport` implementing `NvimTransport` — records calls, returns scripted responses
- [x] 7.2 Create `tests/commands.test.ts` — test each command's transport calls and stdout output
- [x] 7.3 Test review command: request_id generation, notification handling, envelope output
- [x] 7.4 Test dry-run/offline path: auto-accept without transport
- [x] 7.5 Test error cases: transport failure, timeout, malformed response
- [x] 7.6 Create `tests/integration/rpc.test.ts` — spawn headless nvim, test end-to-end review
- [x] 7.7 Integration test: verify `neph status` connects and returns JSON
- [x] 7.8 Integration test: verify `neph set`/`unset` modifies vim.g

## 8. Contract Tests

- [x] 8.1 Create `tests/contract_spec.lua` — load `protocol.json`, assert every method exists in `rpc.lua` dispatch
- [x] 8.2 Create `tests/contract.test.ts` — load `protocol.json`, assert every CLI command references a known method
- [x] 8.3 Validate protocol version field matches between Lua and TS

## 9. Pi Adapter Refactor

- [x] 9.1 Refactor `tools/pi/pi.ts` — replace `shimRun`/`shimQueue` with `neph` CLI spawn
- [x] 9.2 Remove all inline Lua strings and shim-specific logic from pi.ts
- [x] 9.3 Update `tools/pi/tests/pi.test.ts` — mock `neph` spawn instead of `shim` spawn
- [x] 9.4 Verify existing test scenarios pass with new CLI contract
- [x] 9.5 Update `tools.lua` — symlink `neph` CLI instead of `shim.py`

## 10. CI Pipeline Migration

- [x] 10.1 Update `.fluentci/ci.ts` — use `nix develop --no-write-lock-file -c` instead of `nix-shell`
- [x] 10.2 Add `NIX_CONFIG="experimental-features = nix-command flakes"` to container env
- [x] 10.3 Add `npm ci` step for `tools/neph-cli/` in Dagger pipeline
- [x] 10.4 Update `Taskfile.yml` — add `test:cli` target for neph-cli vitest
- [x] 10.5 Update `tools/Taskfile.yml` — replace `test:core` (pytest) with `test:neph` (vitest)
- [x] 10.6 Update `tools/Taskfile.yml` — replace `lint:core` (flake8) with `lint:neph` (eslint or deno lint)
- [ ] 10.7 Verify full `task ci` passes in Dagger locally before any push

## 11. Cleanup

- [x] 11.1 Delete `tools/core/shim.py`
- [x] 11.2 Delete `tools/core/lua/` (open.lua, open_diff.lua, revert.lua)
- [x] 11.3 Delete `tools/core/tests/` (Python test infrastructure)
- [x] 11.4 Delete `tools/core/pyproject.toml`, `tools/core/uv.lock`
- [x] 11.5 Remove Python/flake8 from `flake.nix` devShell buildInputs
- [x] 11.6 Remove `uv` from `flake.nix` devShell buildInputs

## 12. Documentation

- [x] 12.1 Add `mini.doc` to `flake.nix` devShell
- [x] 12.2 Add EmmyLua annotations to all new `lua/neph/api/` modules
- [x] 12.3 Create `scripts/docgen.lua` — generate `doc/neph.txt` via mini.doc
- [x] 12.4 Add `task docs` target to Taskfile.yml
- [x] 12.5 Write `docs/architecture.md` — module boundaries, data flow diagram
- [x] 12.6 Write `docs/rpc-protocol.md` — method catalog, payload shapes, versioning
- [x] 12.7 Write `docs/testing.md` — test structure, how to run, CI pipeline
- [x] 12.8 Update `README.md` — updated architecture overview, installation, agent configuration
