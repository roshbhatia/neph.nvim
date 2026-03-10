## MODIFIED Requirements

### Requirement: README documents socket integration and Lua script location

The README SHALL contain a section explaining `NVIM_SOCKET_PATH` and what it enables. The companion tools table SHALL accurately reference the tools directory structure.

#### Scenario: Socket section present

- **WHEN** the README is read
- **THEN** it contains a "Socket Integration" section with instructions for enabling the socket

#### Scenario: Tools directory reference is accurate

- **WHEN** the README companion tools table is read
- **THEN** directory references SHALL match the actual repository structure
- **AND** stale references to non-existent directories (e.g., `tools/core/lua/`) SHALL be corrected
