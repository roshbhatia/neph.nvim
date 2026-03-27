## ADDED Requirements

### Requirement: open_diff_tab produces non-empty buffers with correct content

Integration tests SHALL call `ui.open_diff_tab()` directly with no stubs and assert the resulting buffers via Neovim API.

#### Scenario: pre-write mode left buffer contains old_lines

- **WHEN** `open_diff_tab(path, old_lines, new_lines, { mode = "pre_write" })` is called
  with `old_lines = {"line A", "line B"}` and `new_lines = {"line A", "line X"}`
- **THEN** a new tab SHALL be created
- **AND** the left buffer SHALL contain exactly `{"line A", "line B"}`
- **AND** the right buffer SHALL contain exactly `{"line A", "line X"}`

#### Scenario: pre-write mode buffers have correct names

- **WHEN** `open_diff_tab(path, old_lines, new_lines, { mode = "pre_write" })` is called
  with `path = "/tmp/neph_test.lua"`
- **THEN** the left buffer name SHALL match `"neph://current/neph_test.lua"`
- **AND** the right buffer name SHALL match `"neph://proposed/neph_test.lua"`

#### Scenario: post-write mode buffers have correct names

- **WHEN** `open_diff_tab(path, old_lines, new_lines, { mode = "post_write" })` is called
- **THEN** the left buffer name SHALL match `"neph://buffer-before/"`
- **AND** the right buffer name SHALL match `"neph://disk-after/"`

#### Scenario: returned ui_state contains valid window handles

- **WHEN** `open_diff_tab` returns a `ui_state` table
- **THEN** `ui_state.tab` SHALL be a valid tabpage
- **AND** `ui_state.left_win` SHALL be a valid window in that tab
- **AND** `ui_state.right_win` SHALL be a valid window in that tab
- **AND** `ui_state.left_buf` SHALL equal the buffer shown in `ui_state.left_win`
- **AND** `ui_state.right_buf` SHALL equal the buffer shown in `ui_state.right_win`

#### Scenario: cleanup closes the tab

- **WHEN** `ui.cleanup(ui_state)` is called after `open_diff_tab`
- **THEN** the tab SHALL no longer be valid (`nvim_tabpage_is_valid` returns false)
