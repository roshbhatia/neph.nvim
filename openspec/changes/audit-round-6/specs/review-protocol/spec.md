## CHANGED Requirements

### Requirement: Post-write file writes check for errors

The `_apply_post_write` function SHALL check `io.open` and `file:write` return values and notify the user on failure.

#### Scenario: Reject revert write failure

- **WHEN** the user rejects all hunks in a post-write review
- **AND** `file:write()` fails (returns nil, err)
- **THEN** the system SHALL call `vim.notify("Neph: failed to revert agent changes: <path>", WARN)`
- **AND** SHALL close the file handle
- **AND** SHALL return without modifying the file

#### Scenario: Partial merge write failure

- **WHEN** the user accepts some hunks in a post-write review
- **AND** `file:write()` fails (returns nil, err)
- **THEN** the system SHALL call `vim.notify("Neph: failed to write merged content: <path>", WARN)`
- **AND** SHALL close the file handle
- **AND** SHALL return without modifying the file
