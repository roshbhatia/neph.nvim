## ADDED Requirements

### Requirement: Consistent error handling across agent types
CLI agents and extension agents SHALL use identical error handling patterns.
Error recovery mechanisms SHALL be equally reliable for all agent types.

#### Scenario: Review error handling symmetry
- **WHEN** a review operation fails for a CLI agent
- **THEN** the CLI SHALL have a result_path fallback
- **AND** SHALL retry or recover appropriately
- **WHEN** a review operation fails for an extension agent
- **THEN** the extension agent SHALL have identical result_path fallback
- **AND** SHALL use identical retry/recovery logic

#### Scenario: Notification failure handling
- **WHEN** RPC notification fails for any agent type
- **THEN** all agent types SHALL have the same fallback behavior
- **AND** SHALL log errors consistently
- **AND** SHALL attempt recovery with same strategies

### Requirement: Unified parameter validation
All RPC calls SHALL validate parameters consistently.
Validation failures SHALL return consistent error formats.

#### Scenario: Review.open parameter validation
- **WHEN** review.open is called with missing parameters
- **THEN** it SHALL return consistent error format for all callers
- **AND** SHALL validate all required parameters
- **AND** SHALL not assume different parameter sets for different agent types

#### Scenario: Parameter default values
- **WHEN** optional parameters are omitted
- **THEN** default values SHALL be consistent for all callers
- **AND** SHALL not depend on agent type
- **AND** SHALL be documented in protocol.json

### Requirement: Consistent logging and diagnostics
All subsystems SHALL log errors with consistent format.
Diagnostic information SHALL be equally available for all failure modes.

#### Scenario: Error logging consistency
- **WHEN** an error occurs in bus subsystem
- **THEN** it SHALL be logged with consistent format
- **WHEN** an error occurs in review subsystem
- **THEN** it SHALL use identical logging format
- **AND** SHALL include same level of diagnostic detail

#### Scenario: Debug information availability
- **WHEN** debugging a CLI agent failure
- **THEN** debug logs SHALL be available in /tmp/neph-debug.log
- **WHEN** debugging an extension agent failure
- **THEN** identical debug logs SHALL be available
- **AND** SHALL include same context information

### Requirement: Symmetric retry logic
Retry logic SHALL be identical for equivalent operations.
Retry configuration SHALL be consistent across subsystems.

#### Scenario: Connection retry symmetry
- **WHEN** a CLI agent loses connection to Neovim
- **THEN** it SHALL use exponential backoff retry logic
- **WHEN** an extension agent loses connection to Neovim
- **THEN** it SHALL use identical exponential backoff parameters
- **AND** SHALL have same maximum retry count

#### Scenario: File operation retry symmetry
- **WHEN** file operations fail for CLI agents
- **THEN** they SHALL retry with specific backoff strategy
- **WHEN** file operations fail for extension agents
- **THEN** they SHALL use identical retry strategy
- **AND** SHALL handle same error conditions