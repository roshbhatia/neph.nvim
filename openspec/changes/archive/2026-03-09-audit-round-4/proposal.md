## Why

Fourth-round audit found 11 actionable bugs across Lua and TypeScript. The most critical: `review = false` in user config crashes nested access, `session.finalize()` can throw leaving reviews stuck, and the companion respawn counter persists across sessions causing permanent sidecar failure. TypeScript side has unhandled async rejections in event handlers and process signal handlers.

## What Changes

- Wrap `session.finalize()` call in `do_finalize()` with pcall to prevent stuck reviews
- Add config type validation — coerce boolean/non-table nested config to `{}` before access
- Reset `respawn_attempts` at the start of `start_sidecar()` when no job is running
- Store ready-detection timer in `td` table in snacks.lua for cleanup on kill
- Wrap async notification handlers with try/catch in gate.ts and index.ts
- Add try/catch to async event handlers in amp/neph-plugin.ts and pi/pi.ts
- Wrap SIGTERM/SIGINT cleanup in try/catch in companion.ts
- Add runtime validation for `decision` field in gate.ts handleResult
- Add runtime validation for params in diff_bridge.ts
- Use atomic write (temp+rename) in diff_bridge.ts writeFileSync

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `review-protocol`: Protect finalize from throwing, leaving review in broken state
- `gemini-companion-server`: Atomic file writes in diff bridge, process signal safety
- `neph-cli`: Validate gate response decision field, wrap async handlers

## Impact

- `lua/neph/api/review/ui.lua` — pcall around finalize
- `lua/neph/internal/companion.lua` — reset respawn counter on fresh start
- `lua/neph/internal/fs_watcher.lua` — config type guard
- `lua/neph/internal/session.lua` — config type guard
- `lua/neph/backends/snacks.lua` — store timer in td for cleanup
- `tools/neph-cli/src/gate.ts` — decision validation, async handler safety
- `tools/neph-cli/src/index.ts` — async handler safety
- `tools/amp/neph-plugin.ts` — try/catch in event handlers
- `tools/pi/pi.ts` — try/catch in event handlers
- `tools/gemini/src/companion.ts` — signal handler safety
- `tools/gemini/src/diff_bridge.ts` — param validation, atomic write
