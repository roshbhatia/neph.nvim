## ADDED Requirements

### Requirement: open_diff_tab buffer/tab invariants

The `open_diff_tab` function SHALL guarantee structural invariants about the Neovim state it creates, regardless of the call context (interactive or RPC).

#### Scenario: left buffer belongs to the new tab's window (not stale current buffer)

- **WHEN** `open_diff_tab` is called from any context (including Neovim RPC message handler)
- **THEN** the `left_buf` in the returned `ui_state` SHALL be the buffer currently displayed in `ui_state.left_win`
- **AND** `nvim_win_get_buf(ui_state.left_win)` SHALL equal `ui_state.left_buf`
- **NOTE**: Implementations SHALL use `nvim_tabpage_get_win(tab)` + `nvim_win_get_buf()` rather than `nvim_get_current_buf()` to guarantee this invariant

#### Scenario: right buffer is displayed in right window

- **WHEN** `open_diff_tab` returns
- **THEN** `nvim_win_get_buf(ui_state.right_win)` SHALL equal `ui_state.right_buf`

#### Scenario: both buffers are non-empty when lines are provided

- **WHEN** `open_diff_tab` is called with non-empty `old_lines` and `new_lines`
- **THEN** `nvim_buf_get_lines(ui_state.left_buf, 0, -1, false)` SHALL equal `old_lines`
- **AND** `nvim_buf_get_lines(ui_state.right_buf, 0, -1, false)` SHALL equal `new_lines`

#### Scenario: both windows are in the returned tab

- **WHEN** `open_diff_tab` returns
- **THEN** `nvim_tabpage_list_wins(ui_state.tab)` SHALL contain both `ui_state.left_win` and `ui_state.right_win`
