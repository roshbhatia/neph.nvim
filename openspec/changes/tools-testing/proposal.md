## Why

The two companion tools bundled in `tools/` — `tools/core/shim.py` (Python msgpack-rpc Neovim client) and `tools/pi/pi.ts` (pi coding-agent extension) — have no automated tests. The legacy `tools/core/nvim-shim` bash script is redundant now that `shim.py` covers all the same commands, and its presence creates confusion. The top-level `Taskfile.yml` and FluentCI pipeline only run Lua tests; tool-level correctness is completely untested. Bugs in the shims are invisible until they surface during an actual agent session.

## What Changes

- **Remove `tools/core/nvim-shim`**: The bash shim is deleted; `shim.py` is the sole Neovim integration shim.
- **Add `tools/core/tests/`**: pytest-based tests for `shim.py` — unit tests for the `NvimRPC` class and each command dispatch path, using a mock Unix socket server so no real Neovim instance is required.
- **Add `tools/pi/tests/`**: Vitest-based tests for `pi.ts` — unit tests for `shimRun`, `preview`, the `write`/`edit` tool override logic, and lifecycle event handlers, using mocked `spawn` and `pi` API objects.
- **Add `tools/Taskfile.yml`**: Defines `test:core`, `test:pi`, and a `test` task that runs both; also `lint:core` and `lint:pi`.
- **Update root `Taskfile.yml`**: Includes `tools/Taskfile.yml` via the `includes` key so `task test` and `task lint` at the repo root run all tool tests automatically.
- **Update `tools/pi/package.json`**: Add Vitest and type dependencies; add `test` and `test:watch` npm scripts.
- **FluentCI picks it up automatically**: `ci.ts` already runs `task lint` and `task test` — no changes needed there.
- **Update `tools/README.md`**: Document how to run tool tests.

## Capabilities

### New Capabilities

- `core-shim-tests`: `tools/core/tests/` contains pytest tests covering `NvimRPC` (connect, send, parse responses), each CLI command handler, error paths (missing socket, bad socket path, unknown command), and the `main()` dispatch.
- `pi-extension-tests`: `tools/pi/tests/` contains Vitest tests covering `shimRun` (spawn mock), `preview` (accept/reject/error paths), `write` tool override, `edit` tool override, lifecycle events (`session_start`, `session_shutdown`, `agent_start`, `agent_end`), and the no-op behaviour when `NVIM_SOCKET_PATH` is absent.
- `tools-taskfile`: `tools/Taskfile.yml` with `test`, `test:core`, `test:pi`, `lint:core`, `lint:pi` tasks; imported at root level.

### Modified Capabilities

- `tool-install`: `nvim-shim` is no longer bundled; `tools.lua` symlink table and `tools/README.md` updated accordingly.

## Impact

- **Deleted**: `tools/core/nvim-shim`
- **New files**: `tools/core/tests/test_shim.py`, `tools/core/tests/conftest.py` (pytest fixtures), `tools/pi/tests/pi.test.ts`, `tools/pi/vitest.config.ts`, `tools/Taskfile.yml`
- **Modified**: `tools/pi/package.json` (add vitest devDeps), `Taskfile.yml` (add includes), `tools/README.md`, `lua/neph/tools.lua` (remove nvim-shim reference), `tools/README.md`
- **No Lua API changes**; no breaking changes to `neph.setup()`.
