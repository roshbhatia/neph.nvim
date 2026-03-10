## ADDED Requirements

### Requirement: Gate timeout uses distinct exit code

The gate command SHALL use exit code 3 for timeout, distinct from exit code 2 for user rejection.

#### Scenario: User rejects review

- **WHEN** the user explicitly rejects all hunks
- **THEN** the gate SHALL exit with code 2

#### Scenario: Review times out

- **WHEN** the review is not completed within 300 seconds
- **THEN** the gate SHALL exit with code 3
- **AND** the timeout envelope SHALL include `{ decision: "timeout", reason: "Review timed out (300s)" }`

#### Scenario: Review accepted

- **WHEN** the user accepts all hunks
- **THEN** the gate SHALL exit with code 0

### Requirement: NephClient.review timeout

The `NephClient.review()` method SHALL include a timeout to prevent indefinite hangs.

#### Scenario: Review completes within timeout

- **WHEN** `NephClient.review()` is called
- **AND** the Lua side sends `neph:review_done` within 300 seconds
- **THEN** the method SHALL resolve with the review envelope

#### Scenario: Review exceeds timeout

- **WHEN** `NephClient.review()` is called
- **AND** no `neph:review_done` is received within 300 seconds
- **THEN** the method SHALL reject with a timeout error
- **AND** the pending request SHALL be cleaned up
