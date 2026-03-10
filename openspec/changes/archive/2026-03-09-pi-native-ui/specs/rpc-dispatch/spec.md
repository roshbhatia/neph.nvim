## ADDED Requirements

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
