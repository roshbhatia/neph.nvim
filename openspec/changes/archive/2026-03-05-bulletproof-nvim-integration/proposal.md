## Why

The pi ↔ shim ↔ Neovim integration is brittle in several ways. The edit tool is registered with the wrong parameter schema (it silently passes `content` where `oldText`/`newText` are expected, so every edit fails). `shimRun` has no timeout (a hung nvim can stall the entire agent indefinitely). The shim's socket has no timeout (blocking `recv()` loops forever on a dead socket). `close-tab` fires after every agent turn regardless of whether the user is mid-review. The shim CLI is hand-rolled `sys.argv` parsing that gives no help text and poor error messages. And the "open file on read" behaviour (`shim open`) hijacks the user's buffer focus on every agent file-read — agents read constantly, so this is extremely disruptive with no benefit proportionate to the interruption.

## What Changes

- **BREAKING FIX**: Replace `createWriteTool` parameters with `createEditTool` parameters in the `edit` tool override in `pi.ts` — the edit tool was advertising `path + content` to the agent instead of `path + oldText + newText`, causing every edit call to structurally fail
- Add a per-call timeout to `shimRun` (configurable, with no timeout for interactive `preview` calls) so a hung or dead nvim instance cannot stall the agent indefinitely
- Add a read timeout to `NvimRPC`'s socket in `shim.py` so a mid-response nvim hang does not block the Python process forever
- Serialise fire-and-forget shim calls behind a promise queue in `pi.ts` so concurrent lifecycle events (open, checktime, set, unset, close-tab) can't race or pile up on the nvim socket
- Guard `close-tab` so it is only called at session shutdown, not on every `agent_end` — preserving open file tabs across multi-turn sessions
- Replace manual `sys.argv` parsing in `shim.py` with [Click](https://click.palletsprojects.com/) for proper `--help`, typed arguments, and clean error messages
- Replace the disruptive `shim open` call on every agent file-read with a non-intrusive read indicator: set `vim.g.pi_reading` to the current file path (statusline-accessible) and surface it in the pi footer via `ctx.ui.setStatus`; clear it on `agent_end`

## Capabilities

### New Capabilities

- `edit-tool-schema`: Correct parameter registration for the edit tool override — uses `createEditTool` schema and delegates to `createEditTool.execute` for the final write
- `shim-timeout`: Timeout envelope for all `shimRun` calls (short for fire-and-forget, none for interactive preview) plus socket-level timeout in `NvimRPC`
- `shim-serialisation`: Sequential promise queue for fire-and-forget shim commands in `pi.ts` to prevent concurrent dispatch to nvim; `close-tab` moved to session shutdown only
- `shim-cli`: Click-based CLI for `shim.py` replacing manual `sys.argv` dispatch
- `read-indicator`: Non-intrusive read indicator using `vim.g.pi_reading` + pi status footer, replacing the disruptive `shim open` / `open.lua` buffer hijack

### Modified Capabilities

<!-- No existing spec-level requirements are changing; this is all new hardening and replacement. -->

## Impact

- `tools/pi/pi.ts` — edit tool registration, `shimRun`, fire-and-forget `shim()`, `agent_end` handler, `tool_call` read handler (replace `shim open` with `shim set`)
- `tools/core/shim.py` — `NvimRPC.__init__` (add socket timeout), `main()` + all commands (rewrite with Click), add `reading` command or reuse `set`
- `tools/core/lua/open.lua` — no longer called by pi.ts; can be kept for manual use or removed
- `tools/pi/tests/pi.test.ts` — update edit-tool tests to use correct params; add timeout, queue, and read-indicator tests
- `tools/core/tests/test_shim.py` — update CLI tests for Click interface; add socket-timeout coverage
- `pyproject.toml` / inline script metadata — add `click` as a dependency
- No Lua changes required for the plugin itself
- No public API (neph.api) changes
