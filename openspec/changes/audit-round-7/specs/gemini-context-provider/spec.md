## ADDED Requirements

### Requirement: Companion debounce timer stop is crash-safe

The companion module SHALL handle invalid timer handles gracefully when stopping debounce timers.

#### Scenario: Invalid timer handle caught silently

- **WHEN** the debounce timer stop is called with an invalid or already-closed timer handle
- **THEN** the error SHALL be caught silently (pcall or equivalent)
- **AND** no uncaught exception SHALL propagate to the caller
