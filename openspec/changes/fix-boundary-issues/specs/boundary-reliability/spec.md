## ADDED Requirements

### Requirement: Reliable bus health monitoring
The bus health timer SHALL not modify the channels table while iterating over it.
The bus health timer SHALL collect dead channels first and unregister them after iteration.

#### Scenario: Health timer iteration safety
- **WHEN** the health timer runs and detects a dead channel
- **AND** multiple channels exist in the table
- **THEN** the timer SHALL collect dead channel names in a separate list
- **AND** SHALL unregister them after completing iteration over all channels
- **AND** SHALL not modify the channels table during iteration

#### Scenario: Health timer cleanup
- **WHEN** the last channel is unregistered
- **THEN** the health timer SHALL stop
- **AND** SHALL clean up its resources

### Requirement: Reliable review result delivery
All agent types SHALL use result_path fallback for review operations.
Extension agents SHALL pass result_path parameter to review.open RPC call.
Review results SHALL be written to a temporary file before notification.

#### Scenario: CLI agent review reliability
- **WHEN** a CLI agent initiates a review
- **AND** the notification to channel_id fails
- **THEN** the result SHALL still be available in the result_path file
- **AND** the CLI SHALL read the result from the file

#### Scenario: Extension agent review reliability
- **WHEN** an extension agent initiates a review
- **AND** the notification to channel_id fails
- **THEN** the result SHALL still be available in the result_path file
- **AND** the extension agent SHALL have a fallback mechanism to read from file

### Requirement: Atomic temporary file operations
Temporary file writes for review results SHALL use atomic rename operations.
Orphaned temporary files SHALL be cleaned up on startup.

#### Scenario: Atomic file write
- **WHEN** writing a review result to disk
- **THEN** the system SHALL write to a temporary file with .tmp suffix
- **AND** SHALL rename the temporary file to the final name atomically
- **AND** SHALL handle rename failures gracefully

#### Scenario: Orphaned file cleanup
- **WHEN** neph.nvim starts up
- **THEN** it SHALL clean up any orphaned .tmp files in the temporary directory
- **AND** SHALL log any cleanup operations performed

### Requirement: Consistent error recovery
All subsystems SHALL recover gracefully from transient failures.
State SHALL remain consistent after recovery.

#### Scenario: Bus recovery from failed ping
- **WHEN** a bus channel fails health check
- **THEN** the channel SHALL be unregistered
- **AND** the bus state SHALL remain consistent
- **AND** no errors SHALL be logged about table iteration

#### Scenario: Review queue recovery from error
- **WHEN** a review operation fails
- **THEN** the queue SHALL maintain its state
- **AND** SHALL continue processing subsequent reviews
- **AND** SHALL log the failure appropriately