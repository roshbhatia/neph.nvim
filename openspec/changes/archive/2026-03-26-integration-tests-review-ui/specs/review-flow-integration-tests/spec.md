## ADDED Requirements

### Requirement: _open_immediate wires to real open_diff_tab

Integration tests SHALL call `_open_immediate()` with the real `ui` module (no stub) and a controlled engine stub that returns a known hunk count.

#### Scenario: pre-write mode opens a tab and returns Review started

- **WHEN** `_open_immediate({ path=<existing file>, content=<different content>, request_id="r1", mode="pre_write" })` is called
  with a real file on disk and content that differs from it
  and the engine stub returning 1 hunk
- **THEN** the return value SHALL be `{ ok = true, msg = "Review started" }`
- **AND** a new tab SHALL be open in the current Neovim instance

#### Scenario: no-changes path returns No changes and does not open a tab

- **WHEN** `_open_immediate(...)` is called and the engine stub returns 0 hunks
- **THEN** the return value SHALL be `{ ok = true, msg = "No changes" }`
- **AND** no new tab SHALL be opened
- **AND** `review_queue.on_complete` SHALL be called with the request_id

#### Scenario: noop provider auto-accepts without opening a tab

- **WHEN** `review.open(params)` is called with `queue.enable = false`
  and the review_provider stub returns `is_enabled_for = false`
- **THEN** the return value SHALL be `{ ok = true, msg = "Review skipped (noop)" }`
- **AND** no new tab SHALL be opened
- **AND** `review_queue.on_complete` SHALL be called

#### Scenario: queue drains to next review after on_complete

- **WHEN** two reviews are enqueued (queue enabled) and the engine stub returns 1 hunk per review
- **AND** `review_queue.on_complete(first_request_id)` is called
- **THEN** the second review SHALL be activated (open_fn called for second params)
- **AND** a tab for the second review SHALL be open

#### Scenario: post-write mode opens tab with buffer vs disk diff

- **WHEN** `_open_immediate({ path=<file>, mode="post_write", request_id="r1" })` is called
  with a file that has different content on disk vs in the Neovim buffer
  and the engine stub returning 1 hunk
- **THEN** a new tab SHALL be open
- **AND** `active_review` SHALL be non-nil with `mode = "post_write"`
