## MODIFIED Requirements

### Requirement: Keymap callbacks guard against invalid buffer

All keymap callbacks in the review UI SHALL check `vim.api.nvim_buf_is_valid(buf)` before accessing any closure state. This prevents stale state access if the buffer is wiped between callback registration and execution.

#### Scenario: Buffer wiped before callback fires

- **GIVEN** a review is active
- **WHEN** the buffer is wiped externally (e.g., `:bwipeout`)
- **AND** a queued keymap callback fires
- **THEN** the callback returns immediately without error

### Requirement: CursorMoved autocmd cleanup

The CursorMoved autocmd registered during `start_review()` SHALL be explicitly cleaned up when the review finalizes, rather than relying solely on returning `true` from the callback.

#### Scenario: Multiple rapid reviews

- **GIVEN** review 1 finalizes
- **AND** review 2 opens immediately after
- **THEN** review 1's CursorMoved autocmd is removed
- **AND** only review 2's CursorMoved autocmd is active
