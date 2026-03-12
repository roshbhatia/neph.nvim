## 1. Review Graceful Exit

- [x] 1.1 In `lua/neph/api/review/init.lua`, add a module-level `active_review` variable that stores `{session, ui_state, result_path, channel_id, request_id}` when a review is active, cleared on completion
- [x] 1.2 Add a `VimLeavePre` autocmd in `review/init.lua` module scope that checks `active_review`, rejects undecided hunks with reason "Neovim exiting", finalizes, and writes result
- [x] 1.3 Add `M.force_cleanup(agent)` function that closes the active review UI and writes result if the review belongs to the given agent; called from session.kill_session()
- [x] 1.4 In `lua/neph/internal/session.lua` `kill_session()`, call `require("neph.api.review").force_cleanup(agent_name)` before clearing the review queue

## 2. Review UI Hardening

- [x] 2.1 In `lua/neph/api/review/ui.lua` `start_review()`, add `if not vim.api.nvim_buf_is_valid(buf) then return end` as first line in every keymap callback
- [x] 2.2 Store the CursorMoved autocmd ID and explicitly delete it in `do_finalize()` using `vim.api.nvim_del_autocmd()`

## 3. Resource Lifecycle Fixes

- [x] 3.1 In `lua/neph/backends/snacks.lua` `cleanup_all()`, iterate terminals and stop/close `ready_timer` if present before closing windows
- [x] 3.2 In `lua/neph/internal/session.lua` `kill_session()`, iterate and stop all `pending_timers` entries for the killed agent (already implemented)
- [x] 3.3 In `lua/neph/internal/fs_watcher.lua` `watch_file()` debounce callback setup, check for existing `debounce_timers[filepath]` and stop/close it before creating a new timer (already implemented)
- [x] 3.4 In `lua/neph/api/review/init.lua` `write_result()`, check `f:write()` return value and log error on failure
- [x] 3.5 In `lua/neph/internal/file_refresh.lua`, change `cfg.interval or 1000` to `(cfg.interval ~= nil) and cfg.interval or 1000`

## 4. RPC Dispatch Safety

- [x] 4.1 In `lua/neph/api/ui.lua`, wrap all `vim.rpcnotify()` calls with pcall (already implemented)

## 5. CLI Fixes

- [x] 5.1 In `tools/neph-cli/src/index.ts`, call `watcher.close()` before `process.exit(0)` on successful review completion (already implemented in handleResult)
- [x] 5.2 In `tools/neph-cli/src/index.ts`, on `watcher.on('error')`, call `cleanup()` and `process.exit(1)`
- [x] 5.3 In `tools/neph-cli/src/index.ts`, use `fs.mkdtempSync()` for the review result temp directory

## 6. Client SDK Fixes

- [x] 6.1 In `tools/lib/neph-client.ts` `disconnect()`, clear `reconnectTimer` with `clearTimeout()` (already implemented)
- [x] 6.2 In `tools/lib/neph-client.ts` `disconnect()`, reject all `pendingRequests` with a disconnect error and clear the map
- [x] 6.3 In `tools/lib/neph-client.ts` `_scheduleReconnect()`, check `this.disconnected` before each reconnect attempt (already implemented)

## 7. Tool Install Safety

- [x] 7.1 In `lua/neph/tools.lua` symlink validation, apply `vim.fn.resolve()` to both source and destination paths before prefix matching (already implemented)

## 8. Tests

- [x] 8.1 Add test for VimLeavePre review finalization (mock active_review, verify write_result called)
- [x] 8.2 Add test for debounce timer replacement in fs_watcher (rapid triggers → single callback)
- [x] 8.3 Add test for NephClient pending request cleanup on disconnect
