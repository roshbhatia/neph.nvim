## Context

`tools/pi/pi.ts` is a pi coding-agent extension that intercepts the `write` and `edit` tools and routes every proposed file change through an interactive vimdiff review in the user's running Neovim instance. The communication channel is a Python helper (`tools/core/shim.py`) that speaks the Neovim msgpack-RPC protocol directly over the Unix socket exported as `NVIM_SOCKET_PATH`.

Three classes of defects make the integration fragile today:

1. **Wrong schema on the edit override.** `pi.ts` calls `createWriteTool(process.cwd()).parameters` for the `edit` tool registration. The write schema is `{ path, content }`, but the agent expects `{ path, oldText, newText }` for edits. Every edit invocation structurally fails because the agent sends `oldText`/`newText` and the override receives `undefined` for both.

2. **No timeouts anywhere.** `shimRun` in `pi.ts` spawns a child process and waits forever for it to exit. Inside the child, `NvimRPC.request()` calls `socket.recv()` in a loop with no deadline. If Neovim is unresponsive (busy, crashed, or in a blocking prompt), both layers hang indefinitely — stalling the entire agent turn or session.

3. **`close-tab` on every turn end.** `agent_end` fires after each agent processing cycle. It unconditionally calls `shim close-tab`, closing the Neovim agent tab. Users who have a file open in that tab lose it between every turn.

4. **Hand-rolled CLI in shim.py.** The current `main()` uses raw `sys.argv` + a `match` block with no `--help`, no typed argument validation, and cryptic error messages. Click gives all of this for free.

5. **`shim open` hijacks buffer focus.** On every agent `read` tool call, `pi.ts` fires `shim open <file>` which forces a tab switch in Neovim. Agents read many files per turn; this is extremely disruptive and does not justify the minor ambient awareness it provides.

## Goals / Non-Goals

**Goals:**
- Fix the edit tool schema so the agent sends and receives `oldText`/`newText` correctly
- Prevent agent hangs by adding timeouts to both `shimRun` (TypeScript) and `NvimRPC` socket (Python)
- Preserve the agent tab across turns; only close it at session shutdown
- Serialise fire-and-forget shim calls so lifecycle commands reach Neovim in deterministic order
- Replace the shim CLI with Click for robustness and discoverability
- Replace `shim open` with a non-intrusive `vim.g.pi_reading` global + pi footer status

**Non-Goals:**
- Re-architecting the shim protocol (msgpack-RPC is correct and stays)
- Supporting Neovim remote plugins or async RPC notifications
- Changing any Lua scripts used for preview/revert (preview.lua, revert.lua are fine)
- Modifying the public neph.nvim API (`neph.api`)

## Decisions

### D1 — Use `createEditTool` for the edit override

The edit override must import and use `createEditTool(cwd).parameters` for registration and `createEditTool(cwd).execute` for the final disk write (after the user accepts). The current code uses `createWriteTool` throughout. The fix is a targeted import addition and two substitution sites. The tests mock `createWriteTool`; they need a parallel mock for `createEditTool`.

*Alternative considered*: Manually define the edit schema inline with `Type.Object({ path, oldText, newText })`. Rejected because `createEditTool` already exposes the canonical schema and keeps us in sync with upstream changes automatically.

### D2 — Two-tier timeout strategy for `shimRun`

Interactive calls (`preview`) must never time out — the user might spend several minutes reviewing a large diff. Fire-and-forget calls (`checktime`, `set`, `unset`, `close-tab`, `revert`) should complete in well under a second under normal conditions; a 15-second timeout is generous and catches hangs without interrupting normal use.

`shimRun` gains an optional `timeoutMs` parameter defaulting to `15_000`. The `preview()` helper passes no `timeoutMs` (no timer). When the timer fires, the child process is `SIGTERM`'d and the promise rejects with a descriptive message.

*Alternative considered*: A single configurable timeout for all calls. Rejected because a timeout that's safe for interactive review (minutes) is useless for detecting a hung `checktime` call.

### D3 — Socket-level timeout in `NvimRPC`

`shim.py` adds `self._sock.settimeout(timeout_secs)` in `NvimRPC.__init__`. The default is `30` seconds. `cmd_preview` passes `timeout=None` (blocking / no timeout) because it is gated by user interaction, not a machine response. All other commands use the default 30-second timeout.

This is a defence-in-depth layer beneath the TypeScript timeout: even if TypeScript's `SIGTERM` is delayed, the Python socket will time out and the shim exits cleanly, letting the TypeScript `close` handler fire.

`NvimRPC.__init__` gains an optional `timeout: float | None = 30.0` parameter. The `connect()` helper accepts and forwards it to `NvimRPC`. `cmd_preview` calls `connect(timeout=None)`.

*Alternative considered*: `socket.setdefaulttimeout()` at module level. Rejected because it cannot be selectively disabled for `cmd_preview`.

### D4 — Serial promise queue for fire-and-forget shim calls

A lightweight serial queue (promise chain) replaces the bare fire-and-forget pattern. The queue is a module-level `Promise<void>` that new tasks append to via `.then()`. Ordering is guaranteed and there is no extra latency for non-overlapping calls.

```ts
let _shimQueue: Promise<void> = Promise.resolve();
function shim(...args: string[]): void {
  _shimQueue = _shimQueue.then(() => shimRun(args, undefined, SHIM_TIMEOUT_MS).catch(() => {}));
}
```

`preview()` calls `shimRun` directly and is NOT routed through the queue.

*Alternative considered*: A true async queue with backpressure. Rejected as over-engineering.

### D5 — Move `close-tab` to session shutdown only

`agent_end` handler drops the `close-tab` call. `session_shutdown` already calls `close-tab`; it is the correct and only place to destroy the tab. The `open` call triggered by `tool_call { toolName: "read" }` survives across turns because the tab is never closed mid-session.

### D6 — Click-based CLI for shim.py

Replace the `main()` dispatch with Click `@cli.command()` subcommands. Each `cmd_*` function becomes the body of a Click command. Arguments are declared with `@click.argument()`. Click handles `--help`, missing argument errors, and unknown command errors automatically. The `shim` entry point becomes a `@click.group()`.

The `preview` command reads proposed content from stdin; Click's `click.get_text_stream('stdin')` is used. All other behaviour remains identical.

Inline script metadata (`# dependencies`) gains `click>=8.0`.

### D7 — Non-intrusive read indicator

Replace the `tool_call` handler's `shim("open", path)` call with:
1. `shim("set", "pi_reading", JSON.stringify(shortPath))` — sets `vim.g.pi_reading` to the short path as a Lua string literal, accessible from the user's Neovim statusline
2. `ctx.ui.setStatus("nvim-reading", shortPath)` — shows the file in the pi footer (non-blocking, no Neovim side effect)

Clear both in `agent_end`: `shim("unset", "pi_reading")` and `ctx.ui.setStatus("nvim-reading", "")`.

The `open.lua` script is retained on disk (for manual use) but is no longer called by `pi.ts`.

*Alternative considered*: Quickfix list. Rejected because the qflist is typically occupied (compile errors, grep results) and even appending to it opens a split. The global variable approach is strictly opt-in and non-disruptive.

## Risks / Trade-offs

- **[Risk] Tab accumulation** — if `session_shutdown` is never fired (force-kill, crash), the agent tab remains open. Mitigation: the existing `agent_tab` global means a new session reuses the same tab.
- **[Risk] Queue starving interactive preview** — fire-and-forget calls queued just before `preview` delay vimdiff opening. Mitigation: preview is called during tool execution; lifecycle events are before/after, not concurrent.
- **[Risk] 15s timeout too short on slow systems** — exported as `SHIM_TIMEOUT_MS` constant for easy tuning.
- **[Risk] `socket.settimeout` raises mid-recv** — a timeout aborts the entire request; partial msgpack state is discarded with the socket. Acceptable since each command opens a fresh connection.
- **[Risk] `vim.g.pi_reading` as Lua string quoting** — path strings with special chars must be properly quoted. Mitigation: use `JSON.stringify(path)` in TypeScript which produces a valid Lua string literal for all ASCII paths; document the limitation for non-ASCII paths.

## Migration Plan

1. Fix `pi.ts`: import `createEditTool`, swap edit registration + execution, add timeout to `shimRun`, add serial queue, remove `close-tab` from `agent_end`, replace `shim open` with set + status
2. Fix `shim.py`: add `timeout` parameter to `NvimRPC.__init__`; thread through `connect()`; rewrite CLI with Click; add `click>=8.0` to inline script dependencies
3. Update tests in `pi.test.ts` and `test_shim.py`
4. Run `task lint` and `task test`; no runtime migration required
