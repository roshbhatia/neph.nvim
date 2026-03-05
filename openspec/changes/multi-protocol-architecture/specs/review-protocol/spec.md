## ADDED Requirements

### Requirement: Review engine (pure logic)

The system SHALL provide a pure Lua module for review logic that is testable without UI.

#### Scenario: Compute hunks
- **WHEN** `engine.compute_hunks(old_lines, new_lines)` is called
- **THEN** it SHALL return an array of hunk ranges with start_line and end_line
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

The review flow SHALL be non-blocking to avoid deadlocks in :terminal buffers.

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
