## ADDED Requirements

### Requirement: Content parameter validation

The review.open handler SHALL validate that the `content` parameter is a string before processing.

#### Scenario: Content is a string

- **WHEN** `review.open` is called with `content = "valid string"`
- **THEN** the review SHALL proceed normally

#### Scenario: Content is nil

- **WHEN** `review.open` is called with `content = nil`
- **THEN** content SHALL default to empty string
- **AND** the review SHALL proceed normally

#### Scenario: Content is not a string

- **WHEN** `review.open` is called with `content = 123` or any non-string non-nil type
- **THEN** the handler SHALL return `{ ok = false, error = "invalid content type" }`
- **AND** no review UI SHALL open

### Requirement: Post-write I/O error surfacing

The `_apply_post_write` function SHALL notify the user when file I/O operations fail.

#### Scenario: io.open fails during reject

- **WHEN** the user rejects all hunks in a post-write review
- **AND** `io.open(file_path, "w")` returns nil
- **THEN** the system SHALL call `vim.notify("Neph: failed to revert agent changes: <path>", WARN)`
- **AND** SHALL return without modifying the file

#### Scenario: io.open fails during partial merge

- **WHEN** the user accepts some hunks in a post-write review
- **AND** `io.open(file_path, "w")` returns nil
- **THEN** the system SHALL call `vim.notify("Neph: failed to write merged content: <path>", WARN)`
- **AND** SHALL return without modifying the file

### Requirement: Nil channel_id skips rpcnotify

The `write_result` function SHALL skip `vim.rpcnotify` when `channel_id` is nil or 0.

#### Scenario: channel_id is nil (fs_watcher-triggered review)

- **WHEN** `write_result` is called with `channel_id = nil`
- **THEN** the file write SHALL proceed normally
- **AND** `vim.rpcnotify` SHALL NOT be called

#### Scenario: channel_id is 0

- **WHEN** `write_result` is called with `channel_id = 0`
- **THEN** `vim.rpcnotify` SHALL NOT be called

#### Scenario: channel_id is a valid positive integer

- **WHEN** `write_result` is called with `channel_id = 5`
- **THEN** `vim.rpcnotify` SHALL be called with that channel_id
