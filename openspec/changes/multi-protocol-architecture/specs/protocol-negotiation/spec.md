## ADDED Requirements

### Requirement: Protocol capability advertisement

The system SHALL allow agents to declare supported protocols in their configuration.

#### Scenario: Agent declares single protocol
- **WHEN** agent config includes `protocol = "rpc"`
- **THEN** system SHALL use RPC protocol exclusively for that agent

#### Scenario: Agent declares multiple protocols in priority order
- **WHEN** agent config includes `protocols = ["websocket", "rpc", "shim"]`
- **THEN** system SHALL attempt protocols in order
- **AND** use first successfully initialized protocol

#### Scenario: Agent uses default protocol
- **WHEN** agent config omits protocol specification
- **THEN** system SHALL default to `shim` protocol for backward compatibility

### Requirement: Protocol initialization

The system SHALL initialize the selected protocol before agent session starts.

#### Scenario: Initialize RPC protocol
- **WHEN** agent selects RPC protocol
- **THEN** system SHALL verify `@neph/client` package is available
- **AND** establish Neovim socket connection
- **AND** fail with error if connection cannot be established

#### Scenario: Initialize WebSocket protocol
- **WHEN** agent selects WebSocket protocol
- **THEN** system SHALL start WebSocket server if not already running
- **AND** write lockfile for client discovery
- **AND** wait for client connection with 5 second timeout

#### Scenario: Initialize Script protocol
- **WHEN** agent selects Script protocol
- **THEN** system SHALL discover tools in toolbox directories
- **AND** invoke describe action on all discovered scripts
- **AND** cache tool schemas

#### Scenario: Fallback to next protocol on failure
- **WHEN** agent protocols list includes multiple options
- **AND** first protocol initialization fails
- **THEN** system SHALL attempt next protocol in list
- **AND** log warning about fallback

### Requirement: Protocol capability checking

The system SHALL verify protocol supports required features before selection.

#### Scenario: Check event streaming support
- **WHEN** agent requires event streaming (file_changed, diagnostics)
- **AND** protocol does not support events (Script protocol)
- **THEN** system SHALL skip that protocol
- **AND** try next protocol in list

#### Scenario: Check bidirectional communication support
- **WHEN** agent requires receiving messages from editor (review workflow)
- **AND** protocol is one-way only
- **THEN** system SHALL skip that protocol

#### Scenario: Agent requirement cannot be satisfied
- **WHEN** all declared protocols lack required capabilities
- **THEN** system SHALL fail agent initialization with clear error
- **AND** suggest compatible protocols for required features

### Requirement: Protocol adapter interface

The system SHALL provide uniform adapter interface across all protocols.

#### Scenario: Call tool via any protocol
- **WHEN** client invokes tool through protocol adapter
- **THEN** adapter SHALL translate to protocol-specific format
- **AND** forward to Lua API
- **AND** translate response back to protocol format

#### Scenario: Stream event via capable protocol
- **WHEN** Lua API emits file_changed event
- **THEN** system SHALL route to all connected clients using event-capable protocols
- **AND** skip clients using protocols without event support

#### Scenario: Query protocol capabilities
- **WHEN** code calls `protocol:capabilities()`
- **THEN** adapter SHALL return table of supported features
- **EXAMPLE** `{ events = true, bidirectional = true, streaming = false }`

### Requirement: Protocol configuration validation

The system SHALL validate protocol configuration at initialization time.

#### Scenario: Reject unknown protocol
- **WHEN** agent config specifies `protocol = "mqtt"`
- **THEN** system SHALL reject configuration with error
- **AND** list valid protocol names

#### Scenario: Warn about deprecated protocol
- **WHEN** agent config specifies `protocol = "shim"`
- **THEN** system SHALL log deprecation warning
- **AND** suggest migration to RPC protocol
- **AND** proceed with shim protocol

#### Scenario: Validate protocol dependencies
- **WHEN** agent selects WebSocket protocol
- **AND** vim.loop is not available (impossible in Neovim ≥ 0.10)
- **THEN** system SHALL fail with dependency error
