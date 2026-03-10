## ADDED Requirements

### Requirement: RPC error responses include stack context

RPC dispatch error responses SHALL include a truncated stack trace to aid debugging.

#### Scenario: Handler throws an error

- **WHEN** an RPC handler throws a Lua error
- **THEN** the error response SHALL include the error message with file and line number context
- **AND** the total error string SHALL be truncated to 500 characters maximum

#### Scenario: Handler returns normally

- **WHEN** an RPC handler returns successfully
- **THEN** the response SHALL be returned as-is without modification
