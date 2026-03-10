## ADDED Requirements

### Requirement: Cancel queued review by file path

The review queue SHALL support cancelling a queued review by file path, without affecting other reviews from the same agent.

#### Scenario: Cancel specific path removes it from queue

- **WHEN** `review_queue.cancel_path("/project/src/foo.lua")` is called
- **AND** a review for `/project/src/foo.lua` is queued (not active)
- **THEN** that review SHALL be removed from the queue
- **AND** other queued reviews SHALL remain unaffected

#### Scenario: Cancel path for active review closes it

- **WHEN** `review_queue.cancel_path("/project/src/foo.lua")` is called
- **AND** the active review is for `/project/src/foo.lua`
- **THEN** the active review SHALL be cancelled
- **AND** the next queued review SHALL open (if any)

#### Scenario: Cancel path with no match is a no-op

- **WHEN** `review_queue.cancel_path("/project/src/bar.lua")` is called
- **AND** no review for that path exists in the queue
- **THEN** the function SHALL return without error
