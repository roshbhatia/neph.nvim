## MODIFIED Requirements

### Requirement: Edit reconstruction replaces all occurrences

The `reconstructEdit` function and equivalent edit handlers SHALL replace ALL occurrences of the old string, not just the first.

#### Scenario: Old string appears multiple times

- **WHEN** the file contains multiple occurrences of `oldStr`
- **THEN** all occurrences SHALL be replaced with `newStr`

### Requirement: File watcher error resilience

The `fs.watch()` calls in gate and review commands SHALL handle watcher errors without crashing.

#### Scenario: Watcher emits error

- **WHEN** the filesystem watcher emits an error event
- **THEN** the error SHALL be logged to stderr
- **AND** the process SHALL NOT crash

## ADDED Requirements

### Requirement: NephClient UI dialog timeout

The `uiSelect()` and `uiInput()` methods SHALL include a timeout to prevent indefinite hangs.

#### Scenario: Dialog not answered within 60 seconds

- **WHEN** `uiSelect()` or `uiInput()` is called
- **AND** no response is received within 60 seconds
- **THEN** the method SHALL resolve with `undefined`
- **AND** the pending request SHALL be cleaned up
