## 1. Fix Edit Tool Schema (`tools/pi/pi.ts`)

- [x] 1.1 Add `createEditTool` to the import from `@mariozechner/pi-coding-agent`
- [x] 1.2 Replace `createWriteTool(process.cwd()).parameters` with `createEditTool(process.cwd()).parameters` in the `edit` tool registration
- [x] 1.3 Replace the `createWriteTool(ctx.cwd).execute(...)` call inside the edit tool's `execute` handler with `createEditTool(ctx.cwd).execute(...)`

## 2. Add Timeout to `shimRun` (`tools/pi/pi.ts`)

- [x] 2.1 Export a constant `SHIM_TIMEOUT_MS = 15_000` near the top of the file for easy tuning
- [x] 2.2 Add an optional `timeoutMs?: number` parameter to `shimRun`; when defined and finite, set a `setTimeout` that kills the child with `SIGTERM` and rejects with `"shim timed out after Xms"`; clear the timer in both the `close` and `error` handlers
- [x] 2.3 Pass `SHIM_TIMEOUT_MS` as `timeoutMs` in the fire-and-forget `shim()` helper
- [x] 2.4 Leave the `preview()` helper calling `shimRun(["preview", filePath], content)` with no `timeoutMs` (interactive, no deadline)

## 3. Add Socket Timeout to `NvimRPC` (`tools/core/shim.py`)

- [x] 3.1 Add `timeout: float | None = 30.0` parameter to `NvimRPC.__init__`; call `self._sock.settimeout(timeout)` after connecting
- [x] 3.2 Update `connect()` to accept and forward a `timeout` argument to `NvimRPC.__init__`
- [x] 3.3 Update all `cmd_*` functions that call `connect()` to pass no extra argument (defaulting to 30s)
- [x] 3.4 Update `cmd_preview` to call `connect(timeout=None)` so the socket stays blocking during user interaction

## 4. Serialise Fire-and-Forget Shim Calls (`tools/pi/pi.ts`)

- [x] 4.1 Add a module-level `let _shimQueue: Promise<void> = Promise.resolve()` variable
- [x] 4.2 Rewrite the `shim()` helper to append to `_shimQueue` via `.then(() => shimRun(args, undefined, SHIM_TIMEOUT_MS).catch(() => {}))` — returns `void`, never awaited
- [x] 4.3 Verify that `preview()` still calls `shimRun` directly (not through the queue)

## 5. Remove `close-tab` from `agent_end` and Fix Read Indicator (`tools/pi/pi.ts`)

- [x] 5.1 Remove the `await shim("close-tab")` call from the `agent_end` event handler
- [x] 5.2 In `agent_end`, add `shim("unset", "pi_reading")` and clear the reading status via `ctx.ui.setStatus`
- [x] 5.3 In `tool_call` handler: replace `shim("open", path)` with `shim("set", "pi_reading", JSON.stringify(shortPath))` and call `ctx.ui.setStatus("nvim-reading", shortPath)` where `shortPath` is the basename/relative path
- [x] 5.4 Confirm `session_shutdown` still calls `shim("close-tab")` (no change needed there)

## 6. Rewrite shim CLI with Click (`tools/core/shim.py`)

- [x] 6.1 Add `click>=8.0` to the inline script `# dependencies` list
- [x] 6.2 Replace the `USAGE` string and `main()` function with a `@click.group()` named `cli`
- [x] 6.3 Convert each `cmd_*` function into a `@cli.command()` with `@click.argument()` for its parameters (e.g., `open` takes `FILE`, `set` takes `NAME` and `LUA_VALUE`, `preview` takes `FILE`)
- [x] 6.4 The `preview` command reads proposed content from `sys.stdin` (unchanged); `click.argument` handles the file path
- [x] 6.5 Replace `if __name__ == "__main__": main()` with `cli()`
- [x] 6.6 Remove the manual `die()` / `connect()` / `cmd_*` dispatch from `main()`; keep `die()` as a utility for socket errors inside cmd functions
- [x] 6.7 Verify `shim --help` and `shim preview --help` produce useful output

## 7. Update TypeScript Tests (`tools/pi/tests/pi.test.ts`)

- [x] 7.1 Add `createEditTool: vi.fn()` to the `vi.mock("@mariozechner/pi-coding-agent")` factory
- [x] 7.2 In `beforeEach`, configure `createEditToolMock` with `parameters: {}` and an `execute` stub
- [x] 7.3 Update edit tool tests: assert `createEditToolMock` execute is called (not `createWriteToolMock`) on accept
- [x] 7.4 Add a test: `shimRun` with an elapsed `timeoutMs` kills the child and the promise rejects with timeout message
- [x] 7.5 Add a test: `agent_end` does NOT call `shim close-tab` (no `close-tab` in spawn calls)
- [x] 7.6 Add a test: `session_shutdown` DOES call `shim close-tab`
- [x] 7.7 Add a test: `tool_call` with `read` calls `shim set pi_reading` (not `shim open`)
- [x] 7.8 Add a test: `agent_end` calls `shim unset pi_reading`

## 8. Update Python Tests (`tools/core/tests/test_shim.py`)

- [x] 8.1 Add a test: `NvimRPC` with default `timeout=30.0` calls `sock.settimeout(30.0)`
- [x] 8.2 Add a test: `NvimRPC` with `timeout=None` does NOT call `sock.settimeout`
- [x] 8.3 Update `TestConnectErrors` and `TestMain` to use Click's error output format (Click writes errors to stderr differently from the old manual `die()`)
- [x] 8.4 Add a test: `shim --help` exits 0 and stdout contains "Usage:"
- [x] 8.5 Add a test: `shim bogus` exits non-zero and stderr contains "No such command"

## 9. Lint and Test

- [x] 9.1 Run `task lint` — fix any deno lint or flake8 warnings introduced
- [x] 9.2 Run `task test` — all Lua, Python, and TypeScript tests pass
