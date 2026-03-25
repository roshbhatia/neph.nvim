## ADDED Requirements

### Requirement: Thread-safe operations in single-threaded async environment
Lua operations SHALL be safe for concurrent async execution.
Shared state modifications SHALL be atomic or protected from reentrancy.

#### Scenario: Review queue atomic operations
- **WHEN** multiple agents enqueue reviews concurrently
- **THEN** the queue SHALL maintain consistent state
- **AND** SHALL not lose any review requests
- **AND** SHALL not corrupt internal data structures
- **AND** SHALL process reviews in the order they were enqueued

#### Scenario: Active review state protection
- **WHEN** multiple operations access the active review state
- **THEN** concurrent modifications SHALL be prevented
- **AND** state transitions SHALL be atomic
- **AND** SHALL not allow race conditions between completion and new activation

#### Scenario: Bus channel state consistency
- **WHEN** channels are registered and unregistered concurrently
- **THEN** the channels table SHALL remain consistent
- **AND** SHALL not allow duplicate registrations
- **AND** SHALL handle unregistration of non-existent channels gracefully

### Requirement: Mutex pattern for Lua async operations
Critical sections SHALL use mutex patterns to prevent reentrancy.
Mutex patterns SHALL be lightweight and non-blocking where possible.

#### Scenario: Non-blocking mutex for review queue
- **WHEN** a review operation is already in progress
- **AND** another operation attempts to modify queue state
- **THEN** the second operation SHALL either wait or retry
- **AND** SHALL not block the main thread indefinitely
- **AND** SHALL eventually complete successfully

#### Scenario: Flag-based reentrancy protection
- **WHEN** using flag-based protection for critical sections
- **THEN** flags SHALL be checked and set atomically
- **AND** SHALL be cleared even if errors occur in the critical section
- **AND** SHALL not deadlock

### Requirement: Async operation ordering guarantees
Async operations initiated in order SHALL complete in order where required.
State dependencies between operations SHALL be respected.

#### Scenario: Sequential review processing
- **WHEN** multiple reviews are enqueued
- **THEN** they SHALL be processed in enqueue order
- **AND** SHALL not skip or reorder reviews
- **AND** SHALL wait for current review to complete before starting next

#### Scenario: Bus operation ordering
- **WHEN** bus operations (register, send_prompt, unregister) are called
- **THEN** they SHALL execute in calling order
- **AND** SHALL maintain channel state consistency across operations
- **AND** SHALL not process stale channel references

### Requirement: Resource cleanup synchronization
Resource cleanup SHALL coordinate with ongoing operations.
Cleanup SHALL not interfere with in-progress operations.

#### Scenario: Cleanup during active review
- **WHEN** cleanup is triggered during an active review
- **THEN** the cleanup SHALL wait for review completion
- **OR** SHALL cancel the review cleanly
- **AND** SHALL not leave resources in inconsistent state

#### Scenario: Concurrent file operations
- **WHEN** multiple processes access temporary files
- **THEN** file operations SHALL use locking or atomic operations
- **AND** SHALL handle "file busy" errors gracefully
- **AND** SHALL retry with exponential backoff where appropriate