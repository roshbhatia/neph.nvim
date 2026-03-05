## MODIFIED Requirements

### Requirement: Shim as optional protocol adapter

The Python shim SHALL transition from being the sole integration point to being one of multiple optional protocol adapters. The shim SHALL remain functional for backward compatibility but is no longer mandatory.

#### Scenario: Shim protocol can be selected explicitly
- **WHEN** agent config specifies `protocol = "shim"`
- **THEN** system SHALL use Python subprocess shim for all tool operations
- **AND** maintain existing shim.py CLI behavior

#### Scenario: Shim is default for backward compatibility
- **WHEN** agent config omits protocol specification
- **AND** agent has not opted into new protocols
- **THEN** system SHALL default to shim protocol
- **AND** behave identically to pre-multi-protocol behavior

#### Scenario: Shim can be bypassed with new protocols
- **WHEN** agent config specifies `protocol = "rpc"` or `protocol = "websocket"`
- **THEN** system SHALL NOT spawn shim.py subprocess
- **AND** SHALL NOT require Python runtime

#### Scenario: Shim marked as legacy in documentation
- **WHEN** user reads protocol comparison documentation
- **THEN** shim protocol SHALL be marked as "legacy"
- **AND** documentation SHALL recommend migration to RPC or WebSocket

## ADDED Requirements

### Requirement: Shim protocol adapter wrapper

The system SHALL provide a protocol adapter that wraps the existing shim.py subprocess implementation.

#### Scenario: Adapter spawns shim subprocess
- **WHEN** tool is invoked via shim protocol
- **THEN** adapter SHALL spawn `uv run shim.py <command>` subprocess
- **AND** capture stdout/stderr
- **AND** return result to caller

#### Scenario: Adapter handles shim timeout
- **WHEN** shim subprocess exceeds timeout (5 seconds for status, 300 seconds for review)
- **THEN** adapter SHALL kill subprocess
- **AND** return timeout error

#### Scenario: Adapter translates shim errors
- **WHEN** shim subprocess exits with non-zero status
- **THEN** adapter SHALL parse stderr
- **AND** translate to protocol-agnostic error type

### Requirement: Deprecation timeline

The system SHALL maintain shim protocol for backward compatibility with planned deprecation.

#### Scenario: No breaking changes in v1.x
- **WHEN** neph.nvim v1.x is released
- **THEN** shim protocol SHALL remain default
- **AND** all existing agent configurations SHALL work without changes

#### Scenario: Deprecation warning in v2.x
- **WHEN** neph.nvim v2.x is released
- **AND** agent uses shim protocol without explicit config
- **THEN** system SHALL log deprecation warning on first use
- **AND** suggest migration to RPC protocol

#### Scenario: Removal in v3.x
- **WHEN** neph.nvim v3.x is released
- **AND** agent config specifies `protocol = "shim"`
- **THEN** system SHALL fail with error
- **AND** provide migration guide to RPC or WebSocket protocol
