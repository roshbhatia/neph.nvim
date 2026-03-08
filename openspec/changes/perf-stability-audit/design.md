## Context

neph.nvim's send path and several utility functions use blocking `vim.fn.system()` calls that freeze Neovim's event loop. The worst offenders are sleep-based polling loops in terminal.lua and wezterm.lua, plus synchronous git calls in context.lua. These were written for simplicity but are unacceptable in production — a 100ms freeze on every prompt send is noticeable, and git calls on large repos can take seconds.

## Goals / Non-Goals

**Goals:**
- Zero blocking calls in the hot path (send, toggle, picker)
- Proper timer/resource cleanup on session teardown
- Graceful error handling instead of crashes on I/O failures

**Non-Goals:**
- Rewriting the backend interface (keep the existing setup/open/focus/hide/show contract)
- Adding new features — this is purely fixing what exists
- Optimizing cold paths that run once (e.g., tools.install already fixed)

## Decisions

### 1. Timer-based waits instead of sleep loops
**Choice:** Replace `vim.fn.system("sleep N")` with `vim.defer_fn()` or `vim.loop.new_timer()`
**Why:** `vim.fn.system()` blocks the entire event loop. `vim.defer_fn()` is the simplest one-shot timer. `vim.loop.new_timer()` for polling patterns that need cancellation.
**Alternative:** `vim.wait()` with a condition — but it still blocks the main loop, just with a timeout.

### 2. Async jobstart for external CLI calls
**Choice:** Replace `vim.fn.system("wezterm cli ...")` and `vim.fn.system("git ...")` with `vim.fn.jobstart()` + callbacks
**Why:** jobstart runs the process asynchronously. The callback fires on completion via `vim.schedule_wrap()`.
**Trade-off:** Send becomes fire-and-forget for wezterm — no synchronous error return. Acceptable because send errors are already best-effort (terminal might be closed).

### 3. Executable cache in agents.lua
**Choice:** Cache `vim.fn.executable()` results in a module-level table, bust on explicit reset
**Why:** `vim.fn.executable()` does a PATH scan. Called per-agent on every picker open (10+ agents = 10+ scans). Cache is valid for the session since agents don't install/uninstall mid-session.

### 4. pcall-wrapped I/O instead of assert
**Choice:** Replace `assert(io.open(...))` with `local f, err = io.open(...)` + nil check
**Why:** `assert` crashes with an unrecoverable error. A missing file during review should show a notification, not kill the session.

### 5. Timer lifecycle via module teardown
**Choice:** Each module that creates a timer exposes a `teardown()` or `cleanup()` function. session.lua calls these on kill/cleanup_all.
**Why:** Timers created with `vim.loop.new_timer()` are GC-weak — they can keep firing after the session ends. Explicit stop/close prevents phantom callbacks.

## Risks / Trade-offs

- **Fire-and-forget send:** Wezterm send errors won't surface synchronously. → Mitigate with `on_exit` callback that notifies on non-zero exit.
- **Executable cache staleness:** If user installs an agent mid-session, picker won't show it. → Acceptable; restart Neovim or call a cache-bust function.
- **Async git context:** Placeholder expansion becomes async, which may require the caller to handle a callback. → If the caller already uses callbacks (input.lua does), this fits naturally. If not, we can use `vim.wait()` with a short timeout as a last resort for cold paths only.
