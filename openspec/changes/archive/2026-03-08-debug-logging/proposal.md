## Why

The entire prompt delivery chain (Lua → CLI → TypeScript extension) is fire-and-forget with no visibility. When pi prompt send fails, there's zero diagnostic information — `catch {}` blocks silently swallow errors, `vim.g` state transitions are invisible, and CLI spawn failures go unnoticed. We need a lightweight debug log that writes to `/tmp` so failures can be diagnosed post-mortem.

## What Changes

- Add a `neph.internal.log` Lua module that writes timestamped debug lines to `/tmp/neph-debug.log`
- Add logging to the TypeScript side (`tools/lib/log.ts`) writing to the same file
- Instrument key points: send_adapter calls, `vim.g.neph_pending_prompt` transitions, CLI spawns, poll results, RPC dispatch, session lifecycle events
- Gate all logging behind `vim.g.neph_debug` (Lua) and `NEPH_DEBUG` env var (TypeScript) — off by default
- Add a `:NephDebug` user command to toggle logging and tail the log file

## Capabilities

### New Capabilities
- `debug-logging`: Structured debug log written to `/tmp/neph-debug.log`, gated behind a flag, covering both Lua and TypeScript sides of the plugin

### Modified Capabilities

## Impact

- New files: `lua/neph/internal/log.lua`, `tools/lib/log.ts`
- Modified files: `lua/neph/agents/pi.lua` (log send_adapter), `lua/neph/internal/session.lua` (log lifecycle), `tools/pi/pi.ts` (log poll loop), `tools/lib/neph-run.ts` (log CLI spawns), `lua/neph/rpc.lua` (log dispatch)
- New user command: `:NephDebug`
- No API changes, no breaking changes, no new dependencies
