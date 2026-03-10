## MODIFIED Requirements

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

## ADDED Requirements

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
