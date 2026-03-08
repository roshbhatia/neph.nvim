## Why

A codebase audit uncovered 32 issues — blocking `vim.fn.system()` calls that freeze Neovim, timer leaks, missing error handling, and unguarded buffer references. The most critical are synchronous sleep/polling loops in terminal.lua, wezterm.lua, and session.lua that lock the editor for hundreds of milliseconds on every send. These need to be converted to non-blocking alternatives for the plugin to be production-quality.

## What Changes

- Replace all blocking `vim.fn.system("sleep ...")` calls with `vim.loop.new_timer()` or `vim.defer_fn()`
- Convert synchronous wezterm CLI calls (`vim.fn.system("wezterm cli ...")`) to `vim.fn.jobstart()` with callbacks
- Replace blocking `io.popen("git ...")` in context.lua with async `vim.fn.jobstart()`
- Cache `vim.fn.executable()` results in agents.lua (called on every picker open)
- Add proper timer lifecycle management (stop/close on teardown) in session.lua and file_refresh.lua
- Guard `assert(io.open())` in review/init.lua with proper error handling
- Add buffer/window validity checks before operations on potentially-stale references
- Wrap jobstart callbacks with `vim.schedule_wrap()` where missing (wezterm backend)

## Capabilities

### New Capabilities
- `async-operations`: Convert all blocking system calls to non-blocking alternatives using timers, jobstart, or vim.schedule
- `resource-lifecycle`: Proper cleanup of timers, buffers, and window references on teardown

### Modified Capabilities
- `send-adapters`: Wezterm send path changes from blocking vim.fn.system() to async jobstart()
- `tool-install`: No changes (already fixed in previous work), but verify stamp-based skip is solid

## Impact

- **Core send path** (session.lua, terminal.lua, wezterm.lua): Every `send()` call touches these — highest traffic code
- **Startup** (agents.lua): Executable caching affects picker responsiveness
- **Git context** (context.lua, placeholders.lua): Affects prompt expansion latency
- **Review flow** (review/init.lua): File I/O crash risk on missing files
- **No API changes**: All fixes are internal — public API signatures unchanged
- **No new dependencies**: Uses existing vim.loop, vim.fn.jobstart, vim.schedule
