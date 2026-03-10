## ADDED Requirements

### Requirement: Gate async handler errors are not silently lost

When `handleResult()` is called from synchronous callbacks (notification handler, fs.watch), its returned Promise must have error handling attached so rejections are logged rather than silently swallowed.

#### Scenario: handleResult throws inside notification handler
- **WHEN** the notification handler calls `handleResult()`
- **AND** the async function rejects
- **THEN** the error is written to stderr

#### Scenario: handleResult throws inside fs.watch callback
- **WHEN** the fs.watch callback calls `handleResult()`
- **AND** the async function rejects
- **THEN** the error is written to stderr

### Requirement: Transport notification listeners are cleaned up on close

#### Scenario: Transport is closed
- **WHEN** `transport.close()` is called
- **THEN** all notification listeners registered via `onNotification()` are removed
