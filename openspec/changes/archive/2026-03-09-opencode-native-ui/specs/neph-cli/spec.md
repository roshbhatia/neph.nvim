## MODIFIED Requirements

### Requirement: Universal CLI bridge

The system SHALL provide a single Node/TS CLI (`neph`) that bridges external programs to Neovim's Lua API via msgpack-rpc.

#### Scenario: RPC agent spawns neph as subprocess
- **WHEN** pi extension calls `spawn("neph", ["review", path], { stdin: content })`
- **THEN** neph SHALL connect to Neovim via `NVIM_SOCKET_PATH`
- **AND** dispatch the review method via `lua/neph/rpc.lua`
- **AND** print ReviewEnvelope JSON to stdout
- **AND** exit 0 on success

#### Scenario: Interactive UI commands
- **WHEN** caller invokes `neph ui-select`, `neph ui-input`, or `neph ui-notify`
- **THEN** neph SHALL dispatch to the corresponding `ui.*` RPC endpoint
- **AND** for `ui-select` and `ui-input`, wait for a notification response before exiting
- **AND** print the result to stdout

#### Scenario: PATH agent discovers neph on PATH
- **WHEN** an agent calls `neph review <path>` with content on stdin
- **THEN** neph SHALL behave identically to subprocess invocation
- **AND** print only JSON to stdout, logs to stderr

#### Scenario: Fire-and-forget commands
- **WHEN** caller invokes `neph set <key> <value>` or `neph checktime`
- **THEN** neph SHALL dispatch via rpc.lua, print nothing to stdout, exit 0

#### Scenario: Self-describing tool schema
- **WHEN** caller invokes `neph spec`
- **THEN** neph SHALL print JSON tool schema describing available commands
- **AND** include input/output shapes for PATH agent discovery
