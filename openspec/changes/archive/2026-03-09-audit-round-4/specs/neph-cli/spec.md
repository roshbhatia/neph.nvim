## ADDED Requirements

### Requirement: Gate decision field validation

The gate SHALL validate the decision field from review results before using it.

#### Scenario: Decision field is undefined or non-string

- **WHEN** the review result JSON is parsed
- **AND** the `decision` field is undefined or not a string
- **THEN** the gate SHALL treat it as "accept" (exit 0, fail-open)

### Requirement: Async notification handlers are error-safe

Async notification handlers SHALL catch and log errors rather than leaving promises unhandled.

#### Scenario: handleResult throws during notification callback

- **WHEN** an async notification handler throws or its promise rejects
- **THEN** the error SHALL be logged to stderr
- **AND** the process SHALL NOT hang from unhandled rejection
