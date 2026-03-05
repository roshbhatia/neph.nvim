## 1. Config schema

- [x] 1.1 Add `review_signs` table to `lua/neph/config.lua` defaults with keys: `accept`, `reject`, `current`, `commented`
- [x] 1.2 Set emoji defaults: `✅`, `❌`, `❓`, `📝`
- [x] 1.3 Document config in module comment with ASCII fallback examples (`+`, `-`, `>`, `*`)

## 2. Hunk range tracking

- [x] 2.1 Add `parse_hunk_ranges(left_buf)` function to `tools/core/lua/open_diff.lua` that returns `{ { start_line, end_line }, ... }`
- [x] 2.2 Use `vim.diff()` or walk buffer with `vim.fn.diff_hlID()` to identify hunk boundaries
- [x] 2.3 Wrap parsing in `pcall()` and emit warning to `:messages` on failure, return empty table as fallback
- [x] 2.4 Call `parse_hunk_ranges()` after `diffthis` and store result in module-local `hunk_ranges` variable
- [x] 2.5 Update `next_hunk()` to increment `hunk_idx` and return `hunk_ranges[hunk_idx]` or nil

## 3. Sign definitions

- [x] 3.1 Define signs `neph_current`, `neph_accept`, `neph_reject`, `neph_commented` via `vim.fn.sign_define()` at module init
- [x] 3.2 Read icon config from `vim.g.neph_config.review_signs` or fall back to emoji defaults
- [x] 3.3 Use sign group `neph_review` for all sign placements
- [x] 3.4 Add `place_sign(sign_name, line)` helper that calls `vim.fn.sign_place(0, "neph_review", sign_name, left_buf, { lnum = line })`
- [x] 3.5 Add `unplace_sign(line)` helper that calls `vim.fn.sign_unplace("neph_review", { buffer = left_buf, id = line })`

## 4. Sign placement logic

- [x] 4.1 Place `neph_current` at `hunk_ranges[1].start_line` after jumping to first hunk
- [x] 4.2 In `y` keymap: call `unplace_sign(current_hunk_line)`, `place_sign("neph_accept", current_hunk_line)` before advancing
- [x] 4.3 In `n` keymap: check if reason is provided; place `neph_commented` if yes, else `neph_reject`
- [x] 4.4 When advancing to next hunk: `unplace_sign(old_line)`, `place_sign("neph_current", new_line)`
- [x] 4.5 In `cleanup()`: call `vim.fn.sign_unplace("neph_review", { buffer = left_buf })` to remove all signs

## 5. Virtual text hints

- [x] 5.1 Create namespace `neph_review_hints` via `vim.api.nvim_create_namespace("neph_review_hints")`
- [x] 5.2 Add `show_hints(hunk)` function that places two extmarks on `right_buf` within `hunk.start_line` to `hunk.end_line` range
- [x] 5.3 Extmark 1: `"← hunk X/Y"` at end of `hunk.start_line` using `virt_text_pos = "eol"`, `hl_group = "DiagnosticInfo"`
- [x] 5.4 Extmark 2: `"[y]es [n]o [a]ll [d]eny [e]dit [?]help"` on `hunk.start_line + 1`, same highlight
- [x] 5.5 Add `clear_hints()` function that calls `nvim_buf_clear_namespace(right_buf, neph_review_hints, 0, -1)`
- [x] 5.6 Call `clear_hints()` then `show_hints(current_hunk)` on first hunk and whenever hunk changes

## 6. Help toggle

- [x] 6.1 Add module-local `show_help` boolean, default `false`
- [x] 6.2 Register `?` keymap on `left_buf` that toggles `show_help` and refreshes hints
- [x] 6.3 Update `show_hints()` to check `show_help`: if true, replace extmark 2 with `"y=accept | n=reject+reason | a=accept-all | d=reject-all | e=manual | [?] hide"`
- [x] 6.4 Ensure `?` keymap descriptor is `"Toggle help"`

## 7. Integration with existing keymaps

- [x] 7.1 Update `y` keymap to call sign placement logic before `next_hunk()`
- [x] 7.2 Update `n` keymap to call sign placement logic (with reason check) before `next_hunk()`
- [x] 7.3 Update `a` keymap to place `neph_accept` signs on all remaining hunks in loop
- [x] 7.4 Update `d` and `<Esc>` keymaps to place `neph_reject` signs on all remaining hunks
- [x] 7.5 Ensure `finalize()` calls `cleanup()` which unplaces all signs

## 8. Testing: Python integration tests

- [x] 8.1 Add `TestReviewVisualFeedback` class to `tools/core/tests/test_shim.py`
- [x] 8.2 Test: `test_review_places_current_sign` — open review in headless nvim, check `sign_getplaced()` for `neph_current`
- [x] 8.3 Test: `test_review_shows_virtual_text` — check `nvim_buf_get_extmarks()` for hint text
- [x] 8.4 Test: `test_config_overrides_sign_icons` — set `vim.g.neph_config.review_signs`, verify custom icons in `sign_getdefined()`
- [x] 8.5 Mark tests with `@pytest.mark.integration` and skip if `NVIM_SOCKET_PATH` absent

Note: Removed placeholder tests that were only skip statements. Visual feedback is best verified through manual testing in actual diff review workflow.

## 9. Documentation

- [x] 9.1 Update `README.md` with `review_signs` config example
- [x] 9.2 Document emoji defaults and ASCII fallback (`+`, `-`, `>`, `*`)
- [x] 9.3 Add screenshot or ASCII art showing diff UI with signs and hints (optional)

## 10. Verification

- [x] 10.1 Run `task lint` — all checks green
- [x] 10.2 Run `task test` — Python and TypeScript tests pass
- [ ] 10.3 Manual test: start pi session, trigger write tool, verify signs and hints visible in diff
- [ ] 10.4 Manual test: press `?`, verify help expands and collapses
- [ ] 10.5 Manual test: accept/reject hunks, verify signs persist and update correctly
