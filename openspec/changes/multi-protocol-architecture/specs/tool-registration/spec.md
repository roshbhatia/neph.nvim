## MODIFIED Requirements

### Requirement: Tool registration via Lua registry

The system SHALL provide a Lua-based tool registry that is independent of specific protocol implementations. Tools are no longer registered exclusively via pi.ts extension overrides but through a centralized Lua registry that protocol adapters can query.

#### Scenario: Register tool from Lua code
- **WHEN** protocol adapter calls `require("neph.registry").register_tool({ name = "write_file", handler = function(...) end })`
- **THEN** tool SHALL be added to central registry
- **AND** be available to all protocol adapters

#### Scenario: Register tool with protocol-specific adapter
- **WHEN** protocol adapter registers tool with `protocol = "websocket"`
- **THEN** tool SHALL include protocol field in registry entry
- **AND** only be invokable via WebSocket protocol

#### Scenario: Query available tools
- **WHEN** code calls `require("neph.registry").list_tools()`
- **THEN** function SHALL return table of all registered tools
- **AND** include tool name, description, and protocol information

#### Scenario: Unregister tool
- **WHEN** protocol adapter calls `require("neph.registry").unregister_tool("write_file")`
- **THEN** tool SHALL be removed from registry
- **AND** subsequent invocations SHALL fail with "tool not found" error

## ADDED Requirements

### Requirement: Tool adapter pattern

The system SHALL provide adapter interface for protocol-specific tool implementations.

#### Scenario: Create tool adapter
- **WHEN** protocol needs custom tool implementation
- **THEN** adapter SHALL implement `describe()` and `execute(input)` methods
- **AND** adapter SHALL be registered with protocol identifier

#### Scenario: Route tool call through adapter
- **WHEN** client invokes tool via protocol
- **THEN** system SHALL look up tool in registry
- **AND** route to protocol-specific adapter if available
- **OR** use default Lua API implementation

#### Scenario: Fallback to default implementation
- **WHEN** tool has no protocol-specific adapter
- **THEN** system SHALL use default adapter wrapping Lua API
- **AND** translate protocol input to Lua function call

### Requirement: Migration from pi.ts overrides

The system SHALL support gradual migration from pi.ts tool overrides to Lua registry.

#### Scenario: Detect legacy pi.ts overrides
- **WHEN** pi agent initializes with legacy extension
- **THEN** system SHALL log deprecation warning
- **AND** continue using pi.ts overrides for backward compatibility

#### Scenario: Opt-in to new registry
- **WHEN** agent config includes `use_lua_registry = true`
- **THEN** system SHALL ignore pi.ts tool overrides
- **AND** use tools from Lua registry exclusively

#### Scenario: Hybrid mode during migration
- **WHEN** agent uses new registry but pi.ts overrides exist
- **AND** `use_lua_registry = false` (default)
- **THEN** pi.ts overrides SHALL take precedence
- **AND** registry tools SHALL be used as fallback
