## CHANGED Requirements

### Requirement: readStdin rejections are caught

The `readStdin()` Promise SHALL have a `.catch()` handler so that stream errors are logged and cause the process to exit.

#### Scenario: stdin stream errors

- **WHEN** `readStdin()` is called
- **AND** the stdin stream emits an error (e.g., broken pipe)
- **THEN** the error SHALL be logged to stderr
- **AND** the process SHALL exit with code 1
