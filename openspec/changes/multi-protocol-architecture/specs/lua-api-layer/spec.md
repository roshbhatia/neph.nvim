## ADDED Requirements

### Requirement: Pure Lua file operations API

The system SHALL provide a pure Lua API for all file operations (write, edit, delete, read) that is independent of any transport protocol.

#### Scenario: Write file via Lua API
- **WHEN** a protocol adapter calls `require("neph.api.write").file(path, content)`
- **THEN** the file SHALL be created or overwritten with the specified content
- **AND** the function SHALL return success status

#### Scenario: Edit file via Lua API
- **WHEN** a protocol adapter calls `require("neph.api.edit").file(path, old_text, new_text)`
- **THEN** the system SHALL find exact match of old_text in the file
- **AND** replace it with new_text
- **AND** return success status with updated content

#### Scenario: Delete file via Lua API
- **WHEN** a protocol adapter calls `require("neph.api.delete").file(path)`
- **THEN** the file SHALL be removed from the filesystem
- **AND** the function SHALL return success status

#### Scenario: Read file via Lua API
- **WHEN** a protocol adapter calls `require("neph.api.read").file(path)`
- **THEN** the function SHALL return the file contents as a string
- **AND** handle binary files appropriately

### Requirement: Path validation

The API SHALL validate all file paths before performing operations.

#### Scenario: Reject invalid path type
- **WHEN** a path argument is not a string
- **THEN** the function SHALL raise a Lua error with descriptive message

#### Scenario: Reject relative paths outside workspace
- **WHEN** a path contains `..` segments that escape the workspace
- **THEN** the function SHALL reject the operation with security error

#### Scenario: Normalize path separators
- **WHEN** a path is provided with mixed separators (forward/backslash)
- **THEN** the system SHALL normalize to platform-appropriate separator

### Requirement: Error handling

The API SHALL provide consistent error handling across all operations.

#### Scenario: File not found for edit
- **WHEN** edit operation is called on non-existent file
- **THEN** the function SHALL return error with "file not found" message
- **AND** SHALL NOT create the file

#### Scenario: Permission denied
- **WHEN** operation fails due to filesystem permissions
- **THEN** the function SHALL return error with "permission denied" message
- **AND** include the specific path in the error

#### Scenario: Exact match not found for edit
- **WHEN** old_text is not found in the file
- **THEN** the function SHALL return error with "exact match not found" message
- **AND** include context showing nearby content

### Requirement: Protocol independence

The API SHALL NOT depend on any specific transport protocol or external runtime.

#### Scenario: Callable from pure Lua unit tests
- **WHEN** API functions are called from plenary test suite
- **THEN** they SHALL execute without requiring Node, Python, or network services

#### Scenario: No protocol-specific types in signatures
- **WHEN** examining API function signatures
- **THEN** they SHALL only use Lua primitive types (string, table, boolean, number)
- **AND** SHALL NOT reference protocol-specific types (WebSocket, RPC channel, etc.)
