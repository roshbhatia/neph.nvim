## ADDED Requirements

### Requirement: Companion debounce timer stop is crash-safe

#### Scenario: Debounce timer becomes invalid before stop
- **WHEN** `push_context` stops the debounce timer
- **AND** the timer handle has become invalid
- **THEN** the error is silently caught and a new timer is created
