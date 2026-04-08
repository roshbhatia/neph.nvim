## ADDED Requirements

### Requirement: save-originating-context

Before opening the diff tab, `open_diff_tab` saves the current window handle and cursor position into `ui_state.originating = { win, cursor }`. This is stored regardless of whether the originating window survives the review session.

### Requirement: restore-on-finish

After the review tab closes and cleanup completes, `finish_review` in `init.lua` restores the originating window and cursor position via `vim.schedule`. Both the `nvim_set_current_win` and `nvim_win_set_cursor` calls are wrapped in `pcall` to handle the case where the originating window was closed during the review.

### Requirement: restore-on-all-exit-paths

Cursor restore fires on all review exit paths: normal submit (`gs`/`q`), manual tab close (TabClosed autocmd), force cleanup (`force_cleanup`), and Neovim exit (VimLeavePre). The restore does not fire on VimLeavePre since Neovim is exiting.
