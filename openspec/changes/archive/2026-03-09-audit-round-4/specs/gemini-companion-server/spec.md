## ADDED Requirements

### Requirement: Diff bridge parameter validation

The diff bridge SHALL validate that filePath and newContent are strings before processing.

#### Scenario: Missing or non-string parameters

- **WHEN** the openDiff tool is called
- **AND** `filePath` or `newContent` is not a string
- **THEN** the handler SHALL return an error response
- **AND** SHALL NOT attempt a file write

### Requirement: Atomic file writes in diff bridge

The diff bridge SHALL use atomic writes (temp file + rename) to prevent file corruption on crash.

#### Scenario: Process crashes during write

- **WHEN** the diff bridge writes accepted content to disk
- **THEN** the write SHALL go to a temporary file first
- **AND** the temporary file SHALL be atomically renamed to the target path

### Requirement: Signal handler error safety

Process signal handlers SHALL catch errors from cleanup to ensure process.exit() is always called.

#### Scenario: cleanup() rejects during SIGTERM

- **WHEN** the process receives SIGTERM
- **AND** the cleanup function throws or rejects
- **THEN** process.exit() SHALL still be called
