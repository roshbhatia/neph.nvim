## ADDED Requirements

### Requirement: Review engine (pure logic)

The system SHALL provide a pure Lua module for review logic that is testable without UI.

#### Scenario: Compute hunks
- **WHEN** `engine.compute_hunks(old_lines, new_lines)` is called
- **THEN** it SHALL return an array of hunk ranges with `start_a`, `end_a` (old-file), `start_b`, `end_b` (new-file)
- **AND** use `vim.diff()` with `result_type = "indices"`

#### Scenario: No differences
- **WHEN** old_lines and new_lines are identical
- **THEN** `compute_hunks` SHALL return an empty array

#### Scenario: Apply decisions
- **WHEN** `engine.apply_decisions(old_lines, new_lines, decisions)` is called
- **THEN** it SHALL return the final content string with accepted hunks applied and rejected hunks preserved from original

#### Scenario: Build envelope
- **WHEN** all hunks are accepted
- **THEN** `build_envelope` SHALL return `{ schema = "review/v1", decision = "accept", content = <final>, hunks = [...] }`

- **WHEN** all hunks are rejected
- **THEN** decision SHALL be `"reject"` and content SHALL be empty string

- **WHEN** some hunks accepted, some rejected
- **THEN** decision SHALL be `"partial"` and content SHALL reflect partial application

### Requirement: Async review protocol

The review flow SHALL be non-blocking to avoid deadlocks in :terminal buffers. The protocol SHALL support both pre-write review (content proposed, not yet on disk) and post-write review (content already on disk, comparing against buffer).

#### Scenario: Review request with correlation
- **WHEN** neph CLI sends `review.open` request
- **THEN** request SHALL include `request_id` (uuid), `result_path`, and `channel_id`
- **AND** Lua SHALL return immediately after opening diff UI

#### Scenario: Atomic result write
- **WHEN** user completes review (accept/reject all hunks)
- **THEN** Lua SHALL write envelope JSON to `result_path.tmp`
- **AND** `os.rename()` to `result_path` (atomic)
- **AND** fire `vim.rpcnotify(channel_id, "neph:review_done", { request_id = request_id })`

#### Scenario: Atomic result write with nil result_path

- **WHEN** user completes a post-write review
- **AND** `result_path` is nil (fs_watcher-triggered review has no CLI caller)
- **THEN** the write_result function SHALL skip file writing
- **AND** SHALL still apply the review decision to the buffer/disk

#### Scenario: Request ID correlation
- **WHEN** neph CLI receives `neph:review_done` notification
- **AND** notification request_id does not match pending review
- **THEN** CLI SHALL ignore the notification

#### Scenario: Timeout
- **WHEN** review is not completed within 300 seconds
- **THEN** neph CLI SHALL print reject envelope with reason "Review timed out"
- **AND** exit 0 (not an error — the agent should handle the rejection)

#### Scenario: Post-write review mode
- **WHEN** `review.open` is called with `mode = "post_write"`
- **THEN** the left buffer SHALL show the Neovim buffer contents (pre-change)
- **AND** the right buffer SHALL show the file contents from disk (post-change)
- **AND** accepting hunks SHALL update the buffer to match disk
- **AND** rejecting hunks SHALL write buffer contents back to disk

#### Scenario: Pre-write review mode (default)
- **WHEN** `review.open` is called without `mode` or with `mode = "pre_write"`
- **THEN** behavior SHALL be unchanged from existing review flow
- **AND** the left buffer SHALL show current file contents
- **AND** the right buffer SHALL show proposed new contents

### Requirement: Review UI (thin adapter)

The review UI SHALL delegate all logic to the engine module.

#### Scenario: Open diff tab
- **WHEN** `review.open` is dispatched
- **THEN** UI SHALL open vimdiff tab with original and proposed content
- **AND** set up signs, winbars, and virtual text hints

#### Scenario: Per-hunk decisions via Snacks picker
- **WHEN** user is positioned on a hunk
- **THEN** UI SHALL present Snacks.picker.select with Accept/Reject/Accept all/Reject all/Manual edit
- **AND** pass decision to engine state machine

#### Scenario: Finalize
- **WHEN** all hunks have decisions
- **THEN** UI SHALL call `engine.build_envelope(decisions)`
- **AND** write result via atomic write
- **AND** fire rpcnotify
- **AND** close diff tab

### Requirement: Review pending RPC method

The RPC dispatch SHALL accept a `review.pending` method to notify the user that a review is waiting.

#### Scenario: review.pending received from gate

- **WHEN** neph-cli sends `review.pending` with `{ path: "/abs/path.lua", agent: "claude" }`
- **THEN** the handler SHALL compute relative path from project root
- **AND** call `vim.notify("Review pending: <rel_path> (<agent>)", vim.log.levels.INFO)`

#### Scenario: review.pending when notifications disabled

- **WHEN** `config.review.pending_notify` is false
- **AND** `review.pending` RPC is received
- **THEN** no notification SHALL be shown

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
