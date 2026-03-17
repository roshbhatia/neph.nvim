## MODIFIED Requirements

### Requirement: Async review protocol

The review flow SHALL be non-blocking to avoid deadlocks in :terminal buffers. The protocol SHALL support both pre-write review (content proposed, not yet on disk) and post-write review (content already on disk, comparing against buffer). The review SHALL be invokable from `neph-cli review` via a single RPC call that returns the decision synchronously to the caller.

#### Scenario: Review request from neph-cli review
- **WHEN** `neph-cli review` sends `review.open` request via `nvim_execute_lua`
- **THEN** request SHALL include `request_id` (uuid), `path`, and `content`
- **AND** Lua SHALL open the diff UI and block via a coroutine or callback until the user decides
- **AND** the RPC call SHALL return the review envelope directly as the return value

#### Scenario: No result_path or channel_id needed
- **WHEN** `review.open` is called from `neph-cli review`
- **THEN** `result_path` and `channel_id` SHALL NOT be required parameters
- **AND** the review envelope SHALL be returned as the RPC response, not written to a temp file

#### Scenario: Timeout
- **WHEN** review is not completed within the caller's timeout
- **THEN** `neph-cli review` SHALL exit with code 3
- **AND** the Lua side SHALL clean up any open review UI when the RPC connection closes

#### Scenario: Post-write review mode
- **WHEN** `review.open` is called with `mode = "post_write"`
- **THEN** the left buffer SHALL show the Neovim buffer contents (pre-change)
- **AND** the right buffer SHALL show the file contents from disk (post-change)
- **AND** accepting hunks SHALL update the buffer to match disk
- **AND** rejecting hunks SHALL write buffer contents back to disk

#### Scenario: Pre-write review mode (default)
- **WHEN** `review.open` is called without `mode` or with `mode = "pre_write"`
- **THEN** the left buffer SHALL show current file contents
- **AND** the right buffer SHALL show proposed new contents

## REMOVED Requirements

### Requirement: Atomic result write
**Reason**: Result routing changes from temp file + notification to synchronous RPC return. The review envelope is returned directly as the `nvim_execute_lua` return value.
**Migration**: `neph-cli review` reads the return value from RPC instead of polling a temp file. No filesystem coordination needed.

### Requirement: Nil channel_id skips rpcnotify
**Reason**: `channel_id` parameter removed from `review.open`. No more `vim.rpcnotify` for review results.
**Migration**: Review results return synchronously via RPC response.

### Requirement: Review pending RPC method
**Reason**: `review.pending` was used by gate.ts to notify before review. With the new architecture, the review opens immediately from `neph-cli review` — no separate pending notification needed.
**Migration**: Remove `review.pending` from protocol.json and RPC dispatch.
