## ADDED Requirements

### Requirement: Review keymaps guard against invalid windows

Keymaps bound during review must not crash if the review windows have been closed or become invalid before the keymap fires.

#### Scenario: User closes review tab then presses a mapped key in another buffer
- **WHEN** a review keymap callback executes
- **AND** `ui_state.left_win` is no longer valid
- **THEN** the callback returns early without error

#### Scenario: User triggers keymap after finalization
- **WHEN** a review keymap callback executes
- **AND** `finalized` is true
- **THEN** the callback returns early without accessing ui_state or session

### Requirement: Async input callbacks guard against stale state

When a keymap opens an async dialog (e.g., `vim.ui.input`), the callback must handle the case where the review was finalized while the dialog was open.

#### Scenario: Review finalizes while reject-reason dialog is open
- **WHEN** the reject keymap opens `vim.ui.input`
- **AND** the user submits the review via another keymap before the input callback fires
- **THEN** the input callback detects `finalized == true` and returns early
