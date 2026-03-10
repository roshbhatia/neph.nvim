## Why

The integration layer between agents and the review system has 16 silent failure points discovered during audit. The most impactful: Gemini's companion sidecar fails silently when its build artifact is missing (user just sees no review), NephClient.review() hangs forever without a timeout, post-write review I/O errors are swallowed (risking file corruption), and bus-to-TTY fallback happens without any user notification. These failures make the review system appear broken when it's actually a missing build or transient error.

## What Changes

- **Companion sidecar**: Show `vim.notify` ERROR when `companion.js` not found (not just debug log), add exponential backoff to respawn, cap retries at 3
- **NephClient.review()**: Add 5-minute timeout matching gate timeout, reject with `"timeout"` reason
- **Post-write I/O errors**: Surface io.open/write failures via `vim.notify` WARN in `_apply_post_write`
- **Bus fallback notification**: When extension agent falls through to TTY send, show one-time WARN notification per agent
- **Content parameter validation**: Validate `content` is a string in `review.open` before calling `:sub()`
- **Gate timeout distinction**: Use exit code 3 for timeout (vs 2 for reject), add `reason` field to timeout envelope
- **Sidecar respawn backoff**: Exponential backoff (2s, 4s, 8s) with max 3 retries, log each attempt
- **Post-write channel_id**: Use `channel_id = nil` instead of `0` for fs_watcher-triggered reviews, skip rpcnotify when nil
- **RPC error context**: Include truncated stack trace in error responses, not just `tostring(result)`

## Capabilities

### New Capabilities

_(none — all fixes are to existing integration paths)_

### Modified Capabilities

- `gemini-companion-server`: Surface missing sidecar script as user notification, add respawn backoff with retry cap
- `review-protocol`: Validate content param, surface post-write I/O errors, skip rpcnotify for nil channel_id
- `neph-cli`: Gate timeout uses distinct exit code, timeout envelope includes reason field
- `agent-bus`: Notify user when extension agent falls back from bus to TTY send
- `rpc-dispatch`: Include stack trace in RPC error responses

## Impact

- **Lua**: `companion.lua`, `session.lua`, `review/init.lua`, `fs_watcher.lua`, `bus.lua`, `rpc.lua`
- **TypeScript**: `neph-client.ts`, `gate.ts`
- **No breaking changes** — all gate exit codes are additive (new code 3), all notifications are informational
