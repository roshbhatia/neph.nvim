## ADDED Requirements

### Requirement: Unified neph_connected status flag

The neph CLI SHALL set `vim.g.neph_connected = true` when a gate or review operation begins, and MUST unset it on completion or error. This provides a single flag for statusline integration.

#### Scenario: Gate sets neph_connected on entry

- **WHEN** `neph gate --agent claude` is invoked with a valid transport
- **THEN** `vim.g.neph_connected` is set to `"true"` before the review flow begins
- **AND** `vim.g.neph_connected` is unset after cleanup completes

#### Scenario: Review command sets neph_connected

- **WHEN** `neph review <path>` is invoked with a valid transport
- **THEN** `vim.g.neph_connected` is set to `"true"` before review.open
- **AND** `vim.g.neph_connected` is unset after cleanup completes

#### Scenario: Cursor post-write sets neph_connected

- **WHEN** `neph gate --agent cursor` is invoked
- **THEN** `vim.g.neph_connected` is set before the checktime call
- **AND** `vim.g.neph_connected` is unset after checktime completes

#### Scenario: No transport skips neph_connected

- **WHEN** a gate or review is invoked but no Neovim socket is found
- **THEN** no `neph_connected` status calls are made
- **AND** the command exits with code 0 (fail-open)

#### Scenario: Cleanup on error or timeout

- **WHEN** the review flow errors or times out
- **THEN** `vim.g.neph_connected` is unset during cleanup
- **AND** the flag does not leak as stale state
