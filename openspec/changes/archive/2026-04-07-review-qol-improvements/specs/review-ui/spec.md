## MODIFIED Requirements

### Requirement: winbar-file-path

**Updated behavior**: `build_winbar` gains a `file_path` parameter. The winbar displays a truncated relative file path (via `vim.fn.fnamemodify(file_path, ":.")`) as the first element, truncated to 35 characters with a leading `…` if longer. Format: `… path/to/file.lua | CURRENT | Hunk 2/7: …`

`refresh_ui` passes `file_path` (from `ui_state`, which holds it from `_open_immediate`'s `file_path` local) to `build_winbar`.

### Requirement: cursor-save-in-open-diff-tab

**Added behavior**: `open_diff_tab` captures `originating = { win = vim.api.nvim_get_current_win(), cursor = vim.api.nvim_win_get_cursor(0) }` before `vim.cmd("tabnew")` and stores it in the returned `ui_state` table.

### Requirement: submit-summary-integration

**Updated behavior**: The `gs` keymap handler in `start_review` calls `show_submit_summary(session, do_finalize)` when `session.get_total_hunks() >= 3`, instead of calling `do_finalize()` directly. For fewer than 3 hunks, existing direct finalize behavior is unchanged.
