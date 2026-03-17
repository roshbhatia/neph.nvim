## MODIFIED Requirements

### Requirement: Dispatch facade

The system SHALL provide a single Lua module (`lua/neph/rpc.lua`) that routes all external RPC calls to API modules. The dispatch table SHALL NOT include bus or extension-agent-specific methods.

#### Scenario: Route known method
- **WHEN** external caller invokes `require("neph.rpc").request("status.set", { name = "pi_active", value = "true" })`
- **THEN** rpc.lua SHALL route to `require("neph.api.status").set(params)`
- **AND** return `{ ok = true, result = <handler_result> }`

#### Scenario: Route review.open
- **WHEN** external caller invokes `require("neph.rpc").request("review.open", { request_id, path, content })`
- **THEN** rpc.lua SHALL route to `require("neph.api.review").open(params)`
- **AND** return the review envelope as the result (synchronous from RPC perspective)

#### Scenario: Unknown method
- **WHEN** external caller invokes `require("neph.rpc").request("bogus.method", {})`
- **THEN** rpc.lua SHALL return `{ ok = false, error = { code = "METHOD_NOT_FOUND", message = "bogus.method" } }`

#### Scenario: Handler error
- **WHEN** a dispatch handler throws a Lua error
- **THEN** rpc.lua SHALL catch via pcall
- **AND** return `{ ok = false, error = { code = "INTERNAL", message = <error_string> } }`

### Requirement: Protocol contract

The dispatch table SHALL be validated against `protocol.json`. The protocol SHALL NOT include `bus.register`, `review.pending`, or any extension-agent-specific methods.

#### Scenario: Contract test
- **WHEN** running `tests/contract_spec.lua`
- **THEN** every method in `protocol.json` SHALL have a corresponding handler in the dispatch table
- **AND** every handler in the dispatch table SHALL be listed in `protocol.json`
- **AND** `bus.register` SHALL NOT be in `protocol.json`
- **AND** `review.pending` SHALL NOT be in `protocol.json`

## REMOVED Requirements

### Requirement: UI Dispatch Endpoints
**Reason**: Renamed — the requirement stays but is unchanged. UI dispatch endpoints (`ui.select`, `ui.input`, `ui.notify`) remain in the dispatch table. No delta needed.
**Migration**: N/A.
