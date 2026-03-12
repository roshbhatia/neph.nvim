## MODIFIED Requirements

### Requirement: File watcher closed on all exit paths

The `fs.watch()` watcher in the review CLI command SHALL be closed on success, error, and timeout paths.

#### Scenario: Review completes successfully

- **WHEN** the review result file is detected
- **THEN** `watcher.close()` is called before `process.exit(0)`

#### Scenario: fs.watch emits error

- **WHEN** `watcher.on('error')` fires
- **THEN** `cleanup()` is called
- **AND** the process exits with code 1

### Requirement: Temp directory security

Review result temp files SHALL use `fs.mkdtempSync()` to create a per-process directory with restricted permissions, rather than writing directly to `/tmp`.

#### Scenario: Temp directory is per-process

- **WHEN** the CLI creates a review result temp file
- **THEN** it SHALL be placed in a directory created by `fs.mkdtempSync()`
- **AND** the directory is unique to the process
