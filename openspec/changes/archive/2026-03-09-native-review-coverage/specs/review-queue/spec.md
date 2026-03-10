## ADDED Requirements

### Requirement: Sequential review queue

The system SHALL maintain a FIFO queue of pending review requests. Only one review SHALL be active at a time.

#### Scenario: First review opens immediately

- **WHEN** `review_queue.enqueue(params)` is called
- **AND** no review is currently active
- **THEN** the review SHALL open immediately via `review.open(params)`

#### Scenario: Concurrent review is queued

- **WHEN** `review_queue.enqueue(params)` is called
- **AND** a review is currently active
- **THEN** the new review SHALL be added to the end of the FIFO queue
- **AND** the review SHALL NOT open until the active review completes

#### Scenario: Next review opens on completion

- **WHEN** the active review completes (accept, reject, or partial)
- **AND** the queue contains pending reviews
- **THEN** the next review in the queue SHALL open automatically

#### Scenario: Queue drains to empty

- **WHEN** the active review completes
- **AND** the queue is empty
- **THEN** no new review SHALL open
- **AND** the active review state SHALL be cleared

### Requirement: Queue count for status display

The review queue SHALL expose the current count of pending reviews for statusline integration.

#### Scenario: Count reflects queue depth

- **WHEN** one review is active and two are queued
- **THEN** `review_queue.count()` SHALL return 2

#### Scenario: Count is zero when idle

- **WHEN** no review is active and the queue is empty
- **THEN** `review_queue.count()` SHALL return 0

#### Scenario: Winbar shows position

- **WHEN** a review is active and 2 reviews are queued
- **THEN** the review UI winbar SHALL display "Review 1/3" (active is 1, total is 3)

### Requirement: Queue cleanup on agent kill

The review queue SHALL discard queued reviews when the associated agent session is killed.

#### Scenario: Kill agent clears its queued reviews

- **WHEN** `session.kill_session("claude")` is called
- **AND** the queue contains 2 reviews from claude and 1 from goose
- **THEN** claude's 2 queued reviews SHALL be discarded
- **AND** goose's queued review SHALL remain

#### Scenario: Active review from killed agent is cancelled

- **WHEN** the active review belongs to a killed agent
- **THEN** the review UI SHALL close
- **AND** the next queued review SHALL open (if any)
