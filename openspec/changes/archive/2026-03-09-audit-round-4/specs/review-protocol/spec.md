## ADDED Requirements

### Requirement: Review finalize error safety

The review UI SHALL handle errors from session.finalize() without leaving the review in a stuck state.

#### Scenario: session.finalize() throws

- **WHEN** the user submits or quits a review
- **AND** `session.finalize()` throws a Lua error
- **THEN** the error SHALL be logged via `vim.notify(ERROR)`
- **AND** the review queue SHALL be notified of completion
- **AND** the review tab SHALL still be cleaned up
