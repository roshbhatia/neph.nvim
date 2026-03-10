## 1. Companion sidecar error surfacing

- [x] 1.1 In `companion.lua:start_sidecar`, replace debug log with `vim.notify(ERROR)` when companion.js not found
- [x] 1.2 Add `vim.notify(ERROR)` when no Neovim server socket is available (line 149-151)
- [x] 1.3 Add respawn attempt counter and exponential backoff (2s, 4s, 8s) — store attempt count in module-level var
- [x] 1.4 Cap respawn at 3 attempts — show `vim.notify(ERROR)` on final failure
- [x] 1.5 Reset respawn counter when sidecar starts successfully (exits with code 0 or stays running beyond initial period)

## 2. NephClient.review timeout

- [x] 2.1 Add 300s timeout to `NephClient.review()` in `tools/lib/neph-client.ts` — reject promise and clean up pending request on timeout
- [x] 2.2 Add test for NephClient.review timeout behavior

## 3. Post-write review I/O error surfacing

- [x] 3.1 In `review/init.lua:_apply_post_write`, add `vim.notify(WARN)` when io.open fails for reject path
- [x] 3.2 Add `vim.notify(WARN)` when io.open fails for partial merge path
- [x] 3.3 Return early after notify — do not proceed with buffer sync on failed write

## 4. Content parameter validation

- [x] 4.1 In `review/init.lua:_open_immediate`, validate `content` is string or nil before processing — return error for other types

## 5. Channel ID nil handling

- [x] 5.1 In `fs_watcher.lua`, use `channel_id = nil` instead of `0` for post-write reviews
- [x] 5.2 In `review/init.lua:write_result`, skip `vim.rpcnotify` when `channel_id` is nil or `0`

## 6. Bus fallback notification

- [x] 6.1 Add `notified_fallback` set (module-level) in `session.lua`
- [x] 6.2 In `session.send()`, show one-time WARN when extension agent falls back to TTY
- [x] 6.3 Clear fallback flag for agent when `bus.register()` succeeds — add callback or hook

## 7. Gate timeout distinction

- [x] 7.1 In `gate.ts`, change timeout exit code from 2 to 3
- [x] 7.2 Add `reason: "Review timed out (300s)"` to timeout envelope
- [x] 7.3 Update gate tests for new exit code

## 8. RPC error context

- [x] 8.1 In `rpc.lua`, capture `debug.traceback()` on handler error and include truncated (500 char) trace in response

## 9. Tests

- [x] 9.1 Add test for companion missing-script notification
- [x] 9.2 Add test for review content validation (non-string input)
- [x] 9.3 Add test for write_result with nil channel_id (no rpcnotify)
- [x] 9.4 Add test for gate timeout exit code 3
