## ADDED Requirements

### Requirement: WebSocket server lifecycle

The system SHALL provide a WebSocket server implementation using vim.loop that starts on demand and cleans up on Neovim exit.

#### Scenario: Start WebSocket server
- **WHEN** an agent with `protocol = "websocket"` is activated
- **THEN** the system SHALL create a TCP server using `vim.loop.new_tcp()`
- **AND** bind to loopback address (127.0.0.1) on random available port
- **AND** write port number to lockfile at `~/.neph/sockets/[pid].lock`

#### Scenario: Cleanup on Neovim exit
- **WHEN** Neovim triggers VimLeavePre autocmd
- **THEN** the system SHALL close all client connections
- **AND** shutdown the TCP server
- **AND** remove the lockfile

#### Scenario: Prevent multiple servers per instance
- **WHEN** WebSocket server is already running
- **AND** second agent requests WebSocket protocol
- **THEN** the system SHALL reuse the existing server
- **AND** NOT create a second TCP listener

### Requirement: Lockfile discovery

The system SHALL provide lockfile-based discovery for external clients.

#### Scenario: Write lockfile on server start
- **WHEN** WebSocket server starts successfully
- **THEN** the system SHALL create lockfile at `vim.fn.stdpath("data")/neph/sockets/[pid].lock`
- **AND** write JSON object containing `{"port": <port>, "pid": <pid>}`

#### Scenario: Client discovers server via lockfile
- **WHEN** external client scans `~/.neph/sockets/` directory
- **THEN** client SHALL find lockfile matching Neovim PID
- **AND** parse JSON to extract port number
- **AND** connect to `127.0.0.1:<port>`

#### Scenario: Cleanup stale lockfiles on startup
- **WHEN** Neovim starts and detects lockfiles from previous crashed sessions
- **THEN** the system SHALL verify PID is not alive
- **AND** remove stale lockfiles

### Requirement: JSON-RPC 2.0 message protocol

The system SHALL implement JSON-RPC 2.0 message format for WebSocket communication.

#### Scenario: Handle request message
- **WHEN** client sends JSON-RPC request `{"jsonrpc": "2.0", "method": "write_file", "params": {...}, "id": 1}`
- **THEN** the system SHALL parse the message
- **AND** route to appropriate Lua API function
- **AND** send response `{"jsonrpc": "2.0", "result": {...}, "id": 1}`

#### Scenario: Handle notification message
- **WHEN** client sends JSON-RPC notification without `id` field
- **THEN** the system SHALL process the request
- **AND** SHALL NOT send a response

#### Scenario: Send error response on invalid request
- **WHEN** client sends malformed JSON or invalid method
- **THEN** the system SHALL send JSON-RPC error response
- **AND** include error code and descriptive message

### Requirement: Event streaming

The system SHALL support streaming events to WebSocket clients for file changes and diagnostics.

#### Scenario: Stream file change event
- **WHEN** a file is modified via Lua API
- **THEN** the system SHALL send JSON-RPC notification to all connected clients
- **WITH** method `file_changed` and params containing `{path, content}`

#### Scenario: Stream diagnostic event
- **WHEN** Neovim diagnostics are updated via LSP
- **THEN** the system SHALL send JSON-RPC notification to subscribed clients
- **WITH** method `diagnostics_updated` and params containing diagnostic list

#### Scenario: Stream selection change event
- **WHEN** user changes visual selection in Neovim
- **THEN** the system SHALL send JSON-RPC notification to subscribed clients
- **WITH** method `selection_changed` and params containing selection range

### Requirement: Connection limits

The system SHALL limit concurrent WebSocket connections to prevent resource exhaustion.

#### Scenario: Accept connection within limit
- **WHEN** client connects and total connections < 5 (default limit)
- **THEN** the system SHALL accept the connection

#### Scenario: Reject connection exceeding limit
- **WHEN** client attempts to connect and total connections >= 5
- **THEN** the system SHALL close the connection immediately
- **AND** log warning about connection limit reached

#### Scenario: Configurable connection limit
- **WHEN** user sets `websocket_max_connections = 10` in config
- **THEN** the system SHALL allow up to 10 concurrent connections
