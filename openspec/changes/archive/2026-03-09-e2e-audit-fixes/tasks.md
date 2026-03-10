## 1. Critical nil guards

- [x] 1.1 Add nil guard for `result_path` in `review/init.lua` write_result — skip file write when nil, still apply decision
- [x] 1.2 Add nil guard for `agent` in `session.lua` companion check (~line 176) — `if not agent then return end`
- [x] 1.3 Add io.open nil guard in `fs_watcher.lua` buffer_differs_from_disk — return false if file deleted

## 2. Error propagation in tools.lua

- [x] 2.1 Wrap all 5 `os.rename()` call sites in tools.lua with `local ok, err = os.rename(...)` and log WARN on failure
- [x] 2.2 Add path traversal validation in `init.lua` — after `vim.fn.expand(sym_spec.dst)`, verify path starts with project root or `$HOME`

## 3. Race condition fixes

- [x] 3.1 Guard companion respawn — check `vim.g.gemini_active` before restarting in the 2s deferred callback
- [x] 3.2 Fix debounce timer accumulation in `fs_watcher.lua` — stop+close existing timer before creating new one for same path
- [x] 3.3 Fix file_refresh double-setup — call `M.teardown()` at top of `M.setup()` to prevent timer leak

## 4. Security hardening

- [x] 4.1 Add `vim.fn.shellescape()` around path argument in `placeholders.lua` git diff command
- [x] 4.2 Validate sym_spec.dst expanded path doesn't escape project root or HOME (task 2.2 covers impl, this is the test)

## 5. Error handling improvements

- [x] 5.1 Log bus health-check failures at debug level in `bus.lua` — capture pcall error and pass to `log.debug("bus", ...)`
- [x] 5.2 Surface `launch_args_fn` errors at WARN level in `session.lua` instead of debug-only
- [x] 5.3 Add pane_id existence check in `session.lua` send() before WezTerm operations

## 6. Config surface expansion

- [x] 6.1 Add `review.fs_watcher.max_watched` to config.lua with default 100, wire into fs_watcher.lua
- [x] 6.2 Add `file_refresh.interval` to config.lua with default 1000, wire into file_refresh.lua
- [x] 6.3 Add EmmyLua annotations for new config fields

## 7. API additions

- [x] 7.1 Add `review_queue.cancel_path(path)` — remove queued review by file path, cancel active if matching
- [x] 7.2 Add `fs_watcher.get_watches()` — return list of currently watched file paths

## 8. Dead code cleanup

- [x] 8.1 Grep for `neph.agents.all` usage — if unused, delete `lua/neph/agents/all.lua`

## 9. Spec compliance

- [x] 9.1 Fix socket-integration spec — update stale `tools/core/lua/` reference to match actual repo structure
- [x] 9.2 Add "Socket Integration" section to README.md documenting NVIM_SOCKET_PATH

## 10. Tests

- [x] 10.1 Add test for write_result with nil result_path in review tests
- [x] 10.2 Add test for fs_watcher buffer_differs_from_disk when file is deleted
- [x] 10.3 Add test for review_queue.cancel_path (new API)
- [x] 10.4 Add test for fs_watcher.get_watches (new API)
- [x] 10.5 Add test for companion respawn guard (vim.g.gemini_active check)
- [x] 10.6 Add test for file_refresh double-setup safety
