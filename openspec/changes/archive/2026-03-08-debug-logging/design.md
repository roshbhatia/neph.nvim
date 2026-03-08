## Context

The neph.nvim prompt delivery chain spans two runtimes (Lua in Neovim, TypeScript in Node) connected by CLI process spawns. When pi prompt send fails, there is zero diagnostic output — `catch {}` blocks swallow errors, `vim.g` state transitions are invisible, and CLI spawn failures go unnoticed. Debugging requires guesswork or manually adding `print()` statements.

## Goals / Non-Goals

**Goals:**
- Provide a single debug log file at `/tmp/neph-debug.log` that both Lua and TypeScript sides append to
- Gate all logging behind explicit opt-in (`vim.g.neph_debug` / `NEPH_DEBUG` env var)
- Log key events: send_adapter calls, vim.g state transitions, CLI spawns, poll results, RPC dispatch
- Keep the logging module minimal — no dependencies, no structured formats, just timestamped lines
- Provide `:NephDebug` command for toggling and tailing

**Non-Goals:**
- Log rotation, compression, or retention policies
- Structured logging (JSON lines, OpenTelemetry)
- Performance metrics or tracing spans
- Logging for non-debug use (user-facing notifications stay as `vim.notify`)

## Decisions

### 1. Single shared log file at `/tmp/neph-debug.log`

Both Lua and TypeScript append to the same file. This gives a unified timeline of events across runtimes without needing log aggregation.

**Alternative considered:** Separate files per runtime (`neph-lua.log`, `neph-ts.log`). Rejected because the whole point is correlating events across the Lua→CLI→TS boundary.

### 2. Append-mode file writes, no buffering

Each log call opens, appends, and closes (Lua: `io.open("a")`; TS: `fs.appendFileSync`). This is slow but safe — no lost lines on crash, no flush concerns.

**Alternative considered:** Buffered writes with periodic flush. Rejected because debug logging is low-volume and crash-safety matters more than throughput.

### 3. Gate behind `vim.g.neph_debug` (Lua) and `NEPH_DEBUG` env var (TS)

Lua side checks `vim.g.neph_debug` on each call — toggleable at runtime. TypeScript side checks `process.env.NEPH_DEBUG` at module load — requires restart to change. The Lua session.open already passes `config.env` to spawned terminals, so setting `NEPH_DEBUG=1` in config.env propagates to TS processes.

**Alternative considered:** Config key in `neph.Config`. Would work but `vim.g.neph_debug` is simpler for runtime toggling and doesn't require re-running setup.

### 4. Log format: `[HH:MM:SS.mmm] [lua|ts] [module] message`

Simple, grep-friendly. The runtime tag (`lua`/`ts`) disambiguates which side logged. Module name (e.g., `session`, `pi-poll`) narrows scope.

### 5. `:NephDebug` command with subcommands

- `:NephDebug on` — sets `vim.g.neph_debug = true`, truncates log file
- `:NephDebug off` — sets `vim.g.neph_debug = nil`
- `:NephDebug tail` — opens log in a split (`:split /tmp/neph-debug.log`)
- `:NephDebug` (no args) — toggles on/off

## Risks / Trade-offs

- **[Interleaved writes]** → Two processes appending to the same file can interleave mid-line on some OS/filesystem combos. Mitigation: each write is a single short line; `O_APPEND` is atomic for small writes on Linux.
- **[Log file grows unbounded]** → If left on, the log file grows forever. Mitigation: `:NephDebug on` truncates the file; user is expected to toggle off when done.
- **[TS env var not runtime-toggleable]** → TypeScript checks env at load. Mitigation: acceptable because the TS side is a long-lived extension that restarts with each pi session. User sets `config.env.NEPH_DEBUG = "1"` in their neph config and restarts pi.
