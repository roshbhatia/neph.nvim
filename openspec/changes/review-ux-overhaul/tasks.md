## 1. Engine: clear_at and tally helpers

- [ ] 1.1 Add `clear_at(idx)` method to `create_session()` that sets `decisions_by_idx[idx] = nil`
- [ ] 1.2 Add `get_tally()` method that returns `{ accepted = N, rejected = N, undecided = N }`
- [ ] 1.3 Add tests for `clear_at` (clear accepted, clear rejected, clear undecided no-op, clear out-of-range)
- [ ] 1.4 Add tests for `get_tally` with various decision states

## 2. Config: new keymap defaults

- [ ] 2.1 Add `undo = "gu"` and `submit = "<CR>"` to `review_keymaps` defaults in `config.lua`

## 3. UI: fix sign off-by-one

- [ ] 3.1 Change sign placement in `refresh_ui()` to use `math.max(1, h.start_a - 1)` for left and `math.max(1, h.start_b - 1)` for right
- [ ] 3.2 Update `jump_to_hunk()` to jump to `h.start_a - 1` (clamped) so cursor aligns with sign
- [ ] 3.3 Update tests in `ui_spec.lua` for adjusted sign line expectations

## 4. UI: force line numbers on both panes

- [ ] 4.1 Move `vim.wo[win].number = true` to after `diffthis` for both windows in `open_diff_tab()`
- [ ] 4.2 Add `WinEnter` autocmd scoped to the review tab that re-forces `number = true` and `signcolumn = "yes"` on both windows
- [ ] 4.3 Clean up the guard autocmd in `cleanup()`

## 5. UI: dual-side signs with inverse semantics

- [ ] 5.1 Add `right_sign_ids = {}` to `ui_state` returned by `open_diff_tab()`
- [ ] 5.2 Refactor `refresh_ui()` sign loop to place signs on both buffers with inverse mapping (accept: ✗ left / ✓ right; reject: ✓ left / ✗ right; reject w/reason: ✓ left / 💬 right; current: → both)
- [ ] 5.3 Update `cleanup()` to unplace signs from both buffers using both sign ID tables
- [ ] 5.4 Update `show_hints()` if needed to avoid conflict with right-side signs

## 6. UI: remove auto-finalize and add explicit submit

- [ ] 6.1 Remove `if session.is_complete() then do_finalize()` from `after_action()`
- [ ] 6.2 Change `after_action()` to stay on current hunk when no undecided hunks remain (instead of finalizing)
- [ ] 6.3 Remove `do_finalize()` from `gA` and `gR` handlers — replace with `refresh_ui()` call
- [ ] 6.4 Add `<CR>` submit keymap: if all decided, finalize; if undecided, prompt via `vim.ui.select` with Submit/Jump/Cancel
- [ ] 6.5 Add `gu` keymap that calls `session.clear_at(idx)` and refreshes UI

## 7. UI: winbar tally

- [ ] 7.1 Update `build_winbar()` to accept tally data and append `✓N ✗N ?N` counts
- [ ] 7.2 Add right-side winbar showing `PROPOSED  ✓N ✗N ?N` in `refresh_ui()`
- [ ] 7.3 Update `build_winbar` keymap hints to include `<CR>=submit` and remove `gA=all gR=reject-all` (keep those discoverable but reduce clutter)
- [ ] 7.4 Update winbar tests for new format

## 8. Integration testing

- [ ] 8.1 Add test: gA with prior decisions preserves them (engine level)
- [ ] 8.2 Add test: gR with prior decisions preserves them (engine level)
- [ ] 8.3 Add test: clear_at followed by is_complete returns false
- [ ] 8.4 Add test: finalize after clear_at treats cleared hunks as rejected with "Undecided"
