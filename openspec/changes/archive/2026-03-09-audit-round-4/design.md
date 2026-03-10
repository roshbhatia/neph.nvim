## Approach

Targeted point fixes. Each finding is a standalone 1-10 line change. No architectural changes needed.

## Key Decisions

### do_finalize pcall
Wrap `on_done(session.finalize())` in pcall. On error, log with vim.notify(ERROR) and still clean up the review queue via `review_queue.on_complete()`. The `finalized` flag is already set before the call, which is correct — it prevents double-finalize.

### Config type validation
In each consumer that accesses nested config (fs_watcher.lua, session.lua, review/init.lua), change `config.review or {}` to `type(config.review) == "table" and config.review or {}`. This handles both nil and boolean false. Apply the same pattern for all nested config access.

### Companion respawn counter reset
Reset `respawn_attempts = 0` at the top of `start_sidecar()` when `sidecar_job` is nil (fresh start, not a respawn). The respawn callback already calls `start_sidecar()` recursively, so we need to only reset when it's a genuinely new session, not a retry.

### Snacks timer cleanup
Store the ready-detection timer as `td.ready_timer` so `M.kill()` can stop and close it.

### Async handler wrapping
For TypeScript notification handlers that are async but registered on sync interfaces, wrap the body in try/catch. For event handlers in amp and pi plugins, add try/catch around all awaited calls.

### Gate decision validation
After JSON.parse in handleResult, validate that `decision` is a string before using it. Default to "accept" (exit 0) for undefined/invalid — this preserves the existing fail-open behavior.

### diff_bridge atomic write
Replace `writeFileSync(path, content)` with write-to-temp + `renameSync(tmp, path)`. Use `${path}.tmp` as temp name.

### diff_bridge param validation
Check that `filePath` and `newContent` are strings before proceeding. Return error response for invalid params.

## Files Changed

| File | Change |
|------|--------|
| `lua/neph/api/review/ui.lua` | pcall around on_done(session.finalize()) |
| `lua/neph/internal/companion.lua` | Reset respawn_attempts on fresh start |
| `lua/neph/internal/fs_watcher.lua` | Config type guard |
| `lua/neph/internal/session.lua` | Config type guard |
| `lua/neph/api/review/init.lua` | Config type guard |
| `lua/neph/backends/snacks.lua` | Store timer in td, cleanup on kill |
| `tools/neph-cli/src/gate.ts` | Decision validation, async handler |
| `tools/neph-cli/src/index.ts` | Async handler wrapping |
| `tools/amp/neph-plugin.ts` | try/catch in event handlers |
| `tools/pi/pi.ts` | try/catch in event handlers |
| `tools/gemini/src/companion.ts` | Signal handler try/catch |
| `tools/gemini/src/diff_bridge.ts` | Param validation, atomic write |
