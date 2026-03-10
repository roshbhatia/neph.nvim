## ADDED Requirements

### Requirement: Pending review notification

When a review request arrives (from gate or extension), the system SHALL notify the user that a review is pending.

#### Scenario: Gate sends pending notification

- **WHEN** neph-cli gate receives a file mutation from claude
- **AND** the gate has a valid transport
- **THEN** the gate SHALL call `review.pending` RPC with `{ path: "<file_path>", agent: "claude" }`
- **AND** Lua SHALL show a notification: "Review pending: <relative_path> (claude)"

#### Scenario: Extension review shows pending notification

- **WHEN** `review_queue.enqueue(params)` is called
- **AND** a review is already active (new review is queued)
- **THEN** a notification SHALL be shown: "Review queued: <relative_path> (<agent>) — 2 pending"

#### Scenario: Notification dismissed when review opens

- **WHEN** a pending review's diff tab opens
- **THEN** the pending notification for that file SHALL be dismissed

### Requirement: Pending notification configuration

The pending notification feature SHALL be configurable.

#### Scenario: Disabled by config

- **WHEN** `config.review.pending_notify` is false
- **THEN** no pending review notifications SHALL be shown

#### Scenario: Enabled by default

- **WHEN** no `review.pending_notify` config is provided
- **THEN** pending review notifications SHALL be shown (default true)

### Requirement: RPC method for pending review

The RPC dispatch SHALL accept a `review.pending` method.

#### Scenario: review.pending RPC received

- **WHEN** neph-cli sends `review.pending` with `{ path: "/abs/path/file.lua", agent: "claude" }`
- **THEN** the RPC handler SHALL compute the relative path from project root
- **AND** SHALL call `vim.notify` with the pending message at INFO level
