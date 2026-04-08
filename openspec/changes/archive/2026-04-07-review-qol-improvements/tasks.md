## 1. Cursor Restore

- [x] 1.1 In `open_diff_tab`, capture `originating = { win = nvim_get_current_win(), cursor = nvim_win_get_cursor(0) }` before `tabnew` and store in returned `ui_state`
- [x] 1.2 In `finish_review` (`init.lua`), after cleanup, call `vim.schedule` to restore originating win + cursor via `pcall`-wrapped `nvim_set_current_win` + `nvim_win_set_cursor`
- [x] 1.3 Ensure restore fires on TabClosed and force_cleanup exit paths (thread `ui_state.originating` through)
- [x] 1.4 Add tests: cursor is restored after normal submit; no crash when originating window closed

## 2. File Path in Winbar

- [x] 2.1 Add `file_path` parameter to `build_winbar`; compute `fnamemodify(path, ":.")` truncated to 35 chars with leading `…`
- [x] 2.2 Update `refresh_ui` to pass `file_path` from `ui_state` to `build_winbar`
- [x] 2.3 Store `file_path` on `ui_state` in `open_diff_tab` (it comes from `_open_immediate` params)
- [x] 2.4 Update `build_winbar` tests for new signature and path display

## 3. Targeted checktime on Accept

- [x] 3.1 In `finish_review` (`init.lua`), after `review_queue.on_complete`, add `vim.schedule` block: find buffer by path, call `checktime` on it if valid
- [x] 3.2 Only trigger for accepted/partial decisions (skip reject path — file unchanged)
- [x] 3.3 Add test: buffer for reviewed file receives checktime after accept

## 4. Debounced Batch Queue Notifications

- [x] 4.1 Add `pending_notify_batch` table and `notify_timer` local to `review_queue.lua`
- [x] 4.2 Replace immediate per-enqueue `vim.notify` (queued path only) with accumulate-into-batch + `vim.defer_fn(400)` logic
- [x] 4.3 On timer fire, emit single `"N reviews queued (agent1, agent2)"` message
- [x] 4.4 Cancel timer and clear batch in `M._reset()`
- [x] 4.5 Add `get_queue()` accessor returning `vim.deepcopy(queue)`
- [x] 4.6 Update queue tests to account for deferred notification timing

## 5. Queue Inspector UI

- [x] 5.1 Create `lua/neph/api/review/queue_ui.lua` with `M.open()` function
- [x] 5.2 Implement floating window render: active review line + numbered queue entries + footer hint
- [x] 5.3 Implement buffer-local keymaps: `dd` (cancel + refresh), `<CR>` (edit file), `r` (refresh), `q`/`<Esc>` (close)
- [x] 5.4 Add `require("neph.api").queue()` function wired to `queue_ui.open()`
- [x] 5.5 Register `:NephQueue` command in `lua/neph/init.lua`
- [x] 5.6 Add tests for queue_ui: renders active + queued entries, dd cancels, empty queue message

## 6. Pre-Submit Summary

- [x] 6.1 Implement `show_submit_summary(session, on_confirm)` local function inside `start_review` in `ui.lua`
- [x] 6.2 Build floating buffer with per-hunk decision lines (✓/✗/?) and footer keymaps
- [x] 6.3 Wire `<CR>` → close + call `on_confirm`; `q`/`<Esc>` → close only
- [x] 6.4 Update `gs` keymap handler: call `show_submit_summary` when `get_total_hunks() >= 3`, else existing behavior
- [x] 6.5 Add tests: summary shown for 3+ hunks, not shown for 2; confirm calls do_finalize; cancel does not

## 7. Gate Winbar Indicator

- [x] 7.1 Create `lua/neph/internal/gate_ui.lua` with `M.set(state, win)` and `M.clear()`
- [x] 7.2 In `set`: store previous winbar, append hold/bypass indicator string to `vim.wo[win].winbar`
- [x] 7.3 In `clear`: restore previous winbar value via `pcall` (window may have closed)
- [x] 7.4 Wire `gate_ui.set("hold", win)` into `M.gate_hold` and `M.gate_bypass` in `api.lua`; wire `gate_ui.clear()` into `M.gate_release` and the normal path of `M.gate`
- [x] 7.5 Add tests: winbar contains indicator after hold/bypass; winbar restored after release; no crash on closed window

## 8. Integration + Cleanup

- [x] 8.1 Run full test suite; fix any regressions
- [x] 8.2 Run `stylua lua/ tests/` and verify no lint errors
- [x] 8.3 Update TESTING.md if new test patterns were introduced
- [x] 8.4 Sync neph.nvim to lazy.nvim managed copy with `/neph-sync-local`
