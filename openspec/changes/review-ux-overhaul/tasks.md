## 1. Fix Sign Alignment

- [x] 1.1 In `ui.lua` `refresh_ui()`, change `math.max(1, h.start_a - 1)` to `h.start_a` for sign placement
- [x] 1.2 In `ui.lua` `jump_to_hunk()`, change `math.max(1, hunks[idx].start_a - 1)` to `hunks[idx].start_a`
- [x] 1.3 In `ui.lua` `show_hints()`, change `math.max(0, hunk_range.start_b - 2)` to use `start_b - 1` (extmark is 0-indexed so `start_b - 1` aligns with the 1-indexed hunk start)

## 2. Left-Side-Only Signs

- [x] 2.1 Remove `right_sign_ids` from `ui_state` returned by `open_diff_tab()`
- [x] 2.2 Remove all `M.place_sign(ui_state.right_buf, ...)` and `M.unplace_sign(ui_state.right_buf, ...)` calls from `refresh_ui()`
- [x] 2.3 Simplify sign logic in `refresh_ui()`: accepted → `neph_accept` (✓), rejected (with or without reason) → `neph_reject` (✗), current undecided → `neph_current` (→), non-current undecided → no sign
- [x] 2.4 Remove `neph_commented` (💬) sign definition from `setup_signs()`
- [x] 2.5 Update `cleanup()` to only unplace signs from `ui_state.left_buf`
- [x] 2.6 Rename `left_sign_ids` to `sign_ids` in ui_state for clarity

## 3. Keybinding Overhaul

- [x] 3.1 Change default keymaps in `start_review()` from `<localleader>a/r/A/R/u` to `ga/gr/gA/gR/gu`
- [x] 3.2 Change submit default from `<S-CR>` to `gs`
- [x] 3.3 Update config schema in `config.lua` to reflect new default keymap values
- [x] 3.4 Remove the `decide` keymap concept — `<CR>` is now hardcoded as the decision menu key (not configurable separately from submit)

## 4. Help Popup

- [x] 4.1 Add `show_help_popup(keymaps)` function that creates a floating window with all keybindings
- [x] 4.2 Bind `?` in the review buffer to toggle the help popup (open if closed, close if open)
- [x] 4.3 Bind `q`, `<Esc>` in the help popup buffer to close it (without triggering review quit)
- [x] 4.4 Help content SHALL read from the resolved `keymaps` table so overrides are reflected
- [x] 4.5 Track help popup window in ui_state; close it on review cleanup if still open

## 5. Explicit Diffopt

- [x] 5.1 In `open_diff_tab()`, save `vim.o.diffopt` to `ui_state.original_diffopt` before setting review diffopt
- [x] 5.2 Set `vim.o.diffopt` to `internal,filler,closeoff,indent-heuristic,inline:char,linematch:60,algorithm:histogram`
- [x] 5.3 Set `vim.wo[left_win].fillchars` and `vim.wo[right_win].fillchars` to include `diff:╌`
- [x] 5.4 In `cleanup()`, restore `vim.o.diffopt` from `ui_state.original_diffopt`
- [x] 5.5 In the `TabClosed` autocmd handler in `init.lua`, also restore diffopt

## 6. Simplified Winbar

- [x] 6.1 Remove `build_right_winbar()` function and all right-window winbar assignments
- [x] 6.2 Update `build_winbar()` to show: mode label, hunk position, tally, queue position, compact hints (`ga=accept gr=reject gs=submit ?=help`)
- [x] 6.3 Remove right-side signcolumn enforcement from the WinEnter guard autocmd (signs are left-only now)

## 7. Update Specs and Tests

- [x] 7.1 Update any existing tests that assert right-side sign placement or `<localleader>` keymaps
- [x] 7.2 Verify `find_hunk_at_cursor()` still works correctly with the alignment fix (uses `start_a`/`end_a` ranges which haven't changed)
