## 1. Lua Log Module

- [x] 1.1 Create `lua/neph/internal/log.lua` with `log.debug(module, fmt, ...)` that appends to `/tmp/neph-debug.log` when `vim.g.neph_debug` is truthy; no-op otherwise
- [x] 1.2 Add test for log module (debug enabled writes file, debug disabled writes nothing)

## 2. Instrument Lua Side

- [x] 2.1 Add debug logging to `lua/neph/agents/pi.lua` send_adapter (log prompt text and submit flag)
- [x] 2.2 Add debug logging to `lua/neph/internal/session.lua` for open, focus, hide, kill_session, and send events
- [x] 2.3 Add debug logging to `lua/neph/rpc.lua` for incoming RPC method calls and results

## 3. TypeScript Log Module

- [x] 3.1 Create `tools/lib/log.ts` with `debug(module, message)` that appends to `/tmp/neph-debug.log` when `NEPH_DEBUG` is set; no-op otherwise
- [x] 3.2 Add Vitest test for TS log module

## 4. Instrument TypeScript Side

- [x] 4.1 Add debug logging to `tools/pi/pi.ts` poll loop (prompt found, no prompt, errors)
- [x] 4.2 Add debug logging to `tools/lib/neph-run.ts` for CLI spawn and exit status

## 5. User Command

- [x] 5.1 Register `:NephDebug` command in `lua/neph/init.lua` with subcommands: on (set flag + truncate log), off (clear flag), tail (open log in split), toggle (no args)
