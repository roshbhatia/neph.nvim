## 1. Remove nvim-shim

- [x] 1.1 Delete `tools/core/nvim-shim` from the repository
- [x] 1.2 Remove any reference to `nvim-shim` from `lua/neph/tools.lua` (it was never in the symlink table, but verify and remove any comment mentioning it)
- [x] 1.3 Update `tools/README.md` to remove the `nvim-shim` section entirely

## 2. Python test infrastructure (tools/core)

- [x] 2.1 Create `tools/core/pyproject.toml` with `[tool.pytest.ini_options]` setting `testpaths = ["tests"]` and `[project.optional-dependencies]` or inline `[dependency-groups]` for pytest and msgpack
- [x] 2.2 Create `tools/core/tests/__init__.py` (empty, makes it a package)
- [x] 2.3 Create `tools/core/tests/conftest.py` with a `nvim_server` pytest fixture: spawns a `threading.Thread` running a `socketserver.UnixStreamServer` on a temp socket path; the server speaks msgpack-rpc (reads a request frame, records `last_call`, replies with a configurable response); fixture yields the server object and shuts down after the test
- [x] 2.4 Create `tools/core/tests/test_shim.py` — NvimRPC tests: successful connect, correct msgpack-rpc frame sent, response returned, RuntimeError on error response, notification frames skipped
- [x] 2.5 Add connect() error-path tests to `test_shim.py`: missing `NVIM_SOCKET_PATH` exits 1 with "not set", non-existent socket path exits 1 with "not found"
- [x] 2.6 Add command dispatch tests to `test_shim.py`: `cmd_open`, `cmd_checktime`, `cmd_set`, `cmd_unset` each verify the correct Lua code / args reach the fake server
- [x] 2.7 Add `cmd_preview` test: patches `sys.stdin` to return `"new content"`, calls against fake server, asserts args `["/file.py", "new content"]` received and JSON result printed to stdout
- [x] 2.8 Add `main()` dispatch tests: unknown command exits 1 with "unknown command", no args exits 1 with "usage"
- [x] 2.9 Verify `uv run pytest tests/ -v` passes from `tools/core/`

## 3. TypeScript test infrastructure (tools/pi)

- [x] 3.1 Add `vitest` and `@vitest/coverage-v8` to `devDependencies` in `tools/pi/package.json`; add `"test": "vitest run"` and `"test:watch": "vitest"` to `scripts`
- [x] 3.2 Create `tools/pi/vitest.config.ts` configuring the test environment (`node`), globals, and include pattern `tests/**/*.test.ts`
- [x] 3.3 Create `tools/pi/tests/pi.test.ts` — mock setup: `vi.mock("node:child_process")` to control spawn; `vi.mock("node:fs")` to control `readFileSync`; `vi.mock("@mariozechner/pi-coding-agent")` to stub `createWriteTool`
- [x] 3.4 Add `shimRun` tests: success resolves with stdout, non-zero exit rejects with stderr message, stdin is written when provided
- [x] 3.5 Add `preview()` tests: accept path, reject path, error/timeout path (shimRun throws)
- [x] 3.6 Add `write` tool override tests: accepted content passed to `createWriteTool().execute`, rejected triggers `shim("revert")` + returns rejection text, partial rejection surfaces note text
- [x] 3.7 Add `edit` tool override tests: file unreadable returns "Cannot read", oldText absent returns "Edit failed" without calling preview, accept path, reject path with revert
- [x] 3.8 Add lifecycle event tests: `session_start` no-op without `NVIM_SOCKET_PATH`, with socket calls `shim("set", "pi_active", "true")` and registers tools; `session_shutdown` calls close-tab + two unsets; `agent_end` calls unset + checktime + close-tab; `tool_call` with `read` calls `shim("open", path)`
- [x] 3.9 Verify `npm test` passes from `tools/pi/`

## 4. Taskfile wiring

- [x] 4.1 Create `tools/Taskfile.yml` with `test:core` (runs `uv run pytest tests/ -v` in `core/`), `test:pi` (runs `npm test` in `pi/`), `test` (deps: `[test:core, test:pi]`), `lint:core` (runs `flake8 core/shim.py`), `lint:pi` (runs `deno lint pi/pi.ts`)
- [x] 4.2 Update root `Taskfile.yml`: add `includes:` block with `tools: { taskfile: tools/Taskfile.yml, dir: tools }`
- [x] 4.3 Update root `test` task to add `deps: [tools:test]` (or add it as a serial `cmds:` entry after the Lua test command)
- [x] 4.4 Update root `lint` task to replace the standalone `deno lint` and `flake8` lines with calls to `tools:lint:pi` and `tools:lint:core` (or add `deps:`) to avoid duplication
- [x] 4.5 Verify `task tools:test` runs from repo root and exits 0

## 5. Docs

- [x] 5.1 Update `tools/README.md`: remove nvim-shim section; add "Running tests" section showing `task tools:test` (from repo root) or `uv run pytest tests/ -v` / `npm test` from each tool directory
