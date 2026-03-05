## Context

`tools/core/shim.py` is a self-contained Python msgpack-rpc client: it opens a Unix socket, exchanges msgpack frames with Neovim, and dispatches to per-command functions. The main testability challenge is the socket dependency — `NvimRPC.__init__` immediately connects. `tools/pi/pi.ts` exports a single factory function that closes over `shimRun` (using `child_process.spawn`) and wires lifecycle events; it's untestable without controlling spawn and the `ExtensionAPI` object. Both tools need tests that run in CI without a live Neovim instance.

## Goals / Non-Goals

**Goals:**
- Delete `tools/core/nvim-shim`; `shim.py` is the only shim
- pytest suite for `shim.py` using a real in-process Unix socket server (no mocking of the socket layer)
- Vitest suite for `pi.ts` with `vi.mock` for `spawn`, `fs`, and `createWriteTool`
- `tools/Taskfile.yml` with granular tasks; root Taskfile includes it via `includes:`
- FluentCI picks up changes automatically (it runs `task test` / `task lint`)

**Non-Goals:**
- Integration tests against a real Neovim process (that's E2E territory)
- Testing the Lua code that runs inside `nvim_exec_lua` (that belongs in the Lua test suite)
- Changing the public API of either tool

## Decisions

### D1: Real Unix socket server for Python tests, not mocked sockets

A real `socketserver.UnixStreamServer` spun up in a `threading.Thread` gives us confidence that the msgpack framing, request/response matching, and notification-skipping logic all work correctly end-to-end. Mocking `socket.socket` would only test our test setup. The server runs on a temp path and is torn down after each test via a pytest fixture.

The server handles the msgpack-rpc request-response protocol: it reads a full frame, returns a configurable response (or error), and lets us assert on what Lua code was sent.

**Alternatives considered:**
- *Mock `socket.socket`*: Simpler setup but misses framing bugs and doesn't test `NvimRPC.request()`'s notification-skip loop.
- *Subprocess the script*: Requires a real nvim socket; not viable in CI.

### D2: Vitest for TypeScript tests, not Jest or Deno test

`pi.ts` uses Node.js built-ins (`child_process`, `fs`, `path`) and is consumed as a Node module. Vitest has first-class support for mocking Node built-ins via `vi.mock("node:child_process")`, auto-imports, and fast ESM transforms — it's the natural fit for this stack. The existing `package.json` already has TypeScript and `@types/node` devDeps.

`vi.mock` at the module level replaces `spawn` globally before any test runs, letting us return controlled stdout/stderr/exit-code sequences. `createWriteTool` from `@mariozechner/pi-coding-agent` is also mocked to return a stub `execute` function.

**Alternatives considered:**
- *Jest*: Requires extra ESM config; Vitest is drop-in for a modern TS project.
- *Deno test*: `pi.ts` imports from `node:` built-ins; mixing Deno and Node is messy.

### D3: `tools/Taskfile.yml` included at root via `includes:`, tasks prefixed `tools:`

Taskfile's `includes` key with a `dir:` allows `task tools:test` to run from the repo root while keeping working directory correct for each sub-tool. The root `test` and `lint` tasks gain `deps: [tools:test]` / `deps: [tools:lint]` so the full suite runs with a single `task test`.

```yaml
# root Taskfile.yml
includes:
  tools:
    taskfile: tools/Taskfile.yml
    dir: tools
```

This means `ci.ts`'s `task test` call now covers Lua tests + Python shim tests + TypeScript extension tests with no changes to the FluentCI pipeline.

### D4: pytest with `uv run pytest` for zero-setup Python test execution

`shim.py` already uses `uv` as its runner. Using `uv run pytest` in the test task means no separate virtual environment management — `uv` resolves `pytest` and `msgpack` automatically from the inline script metadata convention or a `pyproject.toml`.

A minimal `tools/core/pyproject.toml` (or `pytest.ini`) configures the test path so `uv run pytest tests/` works from `tools/core/`.

## Risks / Trade-offs

- **Fake server complexity**: The msgpack-rpc server in conftest.py needs to handle partial reads correctly. → Mitigation: use `msgpack.Unpacker` (same as the production code) in the server.
- **`__dirname` in pi.ts tests**: `shimRun` uses `resolve(__dirname, "../core/shim.py")` to find the shim. In tests, `__dirname` will resolve to the test directory. → Mitigation: mock `spawn` entirely so the shim path is never actually invoked.
- **`@mariozechner/pi-coding-agent` in tests**: `createWriteTool` and `ExtensionAPI` types come from this package. → Mitigation: mock `createWriteTool` with `vi.mock`; construct a manual `pi` stub that satisfies the interface.

## Migration Plan

1. Delete `tools/core/nvim-shim` and update `lua/neph/tools.lua` + `tools/README.md`.
2. Add `tools/core/pyproject.toml` (pytest config + test deps).
3. Write `tools/core/tests/conftest.py` (fake NvimRPC server fixture).
4. Write `tools/core/tests/test_shim.py` (all command tests).
5. Add Vitest to `tools/pi/package.json`; add `vitest.config.ts`.
6. Write `tools/pi/tests/pi.test.ts`.
7. Write `tools/Taskfile.yml`.
8. Update root `Taskfile.yml` with `includes:` and updated `test`/`lint` deps.
9. Update `tools/README.md`.
