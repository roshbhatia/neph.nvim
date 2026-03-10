## ADDED Requirements

### Requirement: Dispatch facade

The system SHALL provide a single Lua module (`lua/neph/rpc.lua`) that routes all external RPC calls to API modules.

#### Scenario: Route known method
- **WHEN** external caller invokes `require("neph.rpc").request("status.set", { name = "pi_active", value = "true" })`
- **THEN** rpc.lua SHALL route to `require("neph.api.status").set(params)`
- **AND** return `{ ok = true, result = <handler_result> }`

#### Scenario: Unknown method
- **WHEN** external caller invokes `require("neph.rpc").request("bogus.method", {})`
- **THEN** rpc.lua SHALL return `{ ok = false, error = { code = "METHOD_NOT_FOUND", message = "bogus.method" } }`

#### Scenario: Handler error
- **WHEN** a dispatch handler throws a Lua error
- **THEN** rpc.lua SHALL catch via pcall
- **AND** return `{ ok = false, error = { code = "INTERNAL", message = <error_string> } }`

### Requirement: Error normalization

All RPC responses SHALL use a consistent envelope format.

#### Scenario: Success response
- **WHEN** handler completes successfully
- **THEN** response SHALL be `{ ok = true, result = <value> }`

#### Scenario: Error response
- **WHEN** handler fails
- **THEN** response SHALL be `{ ok = false, error = { code = <string>, message = <string> } }`

### Requirement: Protocol contract

The dispatch table SHALL be validated against `protocol.json`.

#### Scenario: Contract test
- **WHEN** running `tests/contract_spec.lua`
- **THEN** every method in `protocol.json` SHALL have a corresponding handler in the dispatch table
- **AND** every handler in the dispatch table SHALL be listed in `protocol.json`

### Requirement: UI Dispatch Endpoints
The `rpc.lua` dispatcher SHALL route `ui.select`, `ui.input`, and `ui.notify` methods to a dedicated `neph.api.ui` module.

#### Scenario: Route ui.select
- **WHEN** external caller invokes `require("neph.rpc").request("ui.select", params)`
- **THEN** rpc.lua SHALL route to `require("neph.api.ui").select(params)`

#### Scenario: Route ui.input
- **WHEN** external caller invokes `require("neph.rpc").request("ui.input", params)`
- **THEN** rpc.lua SHALL route to `require("neph.api.ui").input(params)`

#### Scenario: Route ui.notify
- **WHEN** external caller invokes `require("neph.rpc").request("ui.notify", params)`
- **THEN** rpc.lua SHALL route to `require("neph.api.ui").notify(params)`

### Requirement: RPC error responses include stack context

RPC dispatch error responses SHALL include a truncated stack trace to aid debugging.

#### Scenario: Handler throws an error

- **WHEN** an RPC handler throws a Lua error
- **THEN** the error response SHALL include the error message with file and line number context
- **AND** the total error string SHALL be truncated to 500 characters maximum

#### Scenario: Handler returns normally

- **WHEN** an RPC handler returns successfully
- **THEN** the response SHALL be returned as-is without modification
