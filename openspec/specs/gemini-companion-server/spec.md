## ADDED Requirements

### Requirement: MCP HTTP server lifecycle
The companion server SHALL run as a TypeScript sidecar process managed by neph. It SHALL start an HTTP server on a dynamically assigned port (port 0) and accept MCP JSON-RPC 2.0 requests.

#### Scenario: Server starts on dynamic port
- **WHEN** the companion sidecar process is launched
- **THEN** it SHALL bind an HTTP server to port 0 (OS-assigned)
- **AND** the actual port SHALL be available for discovery file creation

#### Scenario: Server handles JSON-RPC 2.0 requests
- **WHEN** a POST request arrives at the server endpoint
- **AND** the body contains a valid JSON-RPC 2.0 message
- **THEN** the server SHALL route to the appropriate tool handler
- **AND** respond with a JSON-RPC 2.0 result

#### Scenario: Server rejects invalid requests
- **WHEN** a request arrives with malformed JSON or missing JSON-RPC fields
- **THEN** the server SHALL respond with a JSON-RPC 2.0 error (code -32700 or -32600)

### Requirement: Discovery file management
The companion SHALL write a discovery file to `os.tmpdir()/gemini/ide/` on startup and remove it on shutdown.

#### Scenario: Discovery file created on startup
- **WHEN** the MCP server is listening on a port
- **THEN** the companion SHALL create `gemini-ide-server-{PID}-{PORT}.json` in the gemini/ide temp directory
- **AND** the file SHALL contain `port`, `workspacePath`, `authToken`, and `ideInfo` fields
- **AND** `ideInfo.name` SHALL be `"neovim"` and `ideInfo.displayName` SHALL be `"Neovim (neph)"`

#### Scenario: Discovery file cleaned up on shutdown
- **WHEN** the companion process receives SIGTERM or SIGINT
- **THEN** it SHALL delete the discovery file before exiting

#### Scenario: Discovery file cleaned up on Neovim exit
- **WHEN** VimLeavePre fires in Neovim
- **THEN** neph SHALL terminate the companion sidecar process
- **AND** the sidecar SHALL clean up its discovery file

### Requirement: Bearer token authentication
The companion SHALL generate a cryptographically random token and validate it on every request.

#### Scenario: Valid token accepted
- **WHEN** a request includes `Authorization: Bearer {token}` matching the generated token
- **THEN** the server SHALL process the request normally

#### Scenario: Missing or invalid token rejected
- **WHEN** a request is missing the Authorization header or has an incorrect token
- **THEN** the server SHALL respond with HTTP 401 Unauthorized
- **AND** SHALL NOT process the MCP message

### Requirement: Neovim connection via NephClient
The companion sidecar SHALL connect to Neovim via NephClient and register on the agent bus as "gemini". The companion SHALL ensure that ALL file writes initiated by Gemini route through the `openDiff` MCP tool, which calls `NephClient.review()`. If Gemini writes a file through a path that does not call `openDiff`, the filesystem watcher SHALL serve as a safety net to detect the change.

#### Scenario: Sidecar connects and registers
- **WHEN** the sidecar process starts with NVIM_SOCKET_PATH set
- **THEN** it SHALL create a NephClient, connect to the socket, and call `register("gemini")`
- **AND** `vim.g.gemini_active` SHALL be set to `true`

#### Scenario: Sidecar reconnects after socket disconnect
- **WHEN** the Neovim socket disconnects unexpectedly
- **THEN** NephClient's built-in reconnect logic SHALL re-establish the connection
- **AND** SHALL re-register as "gemini" on the bus

#### Scenario: openDiff writes file after review approval
- **WHEN** Gemini calls the `openDiff` MCP tool with a file path and new content
- **AND** the user accepts the review (fully or partially)
- **THEN** the companion SHALL write the approved content to disk
- **AND** SHALL call `neph.checktime()` to reload buffers

#### Scenario: openDiff rejects write on user rejection
- **WHEN** Gemini calls `openDiff` and the user rejects all hunks
- **THEN** the companion SHALL NOT write to disk
- **AND** SHALL send `ide/diffRejected` notification to Gemini

### Requirement: Sidecar process management from Lua
neph SHALL spawn and manage the companion sidecar process lifecycle.

#### Scenario: Sidecar starts with Gemini terminal session
- **WHEN** a Gemini agent terminal session is opened via neph
- **THEN** neph SHALL spawn the companion sidecar via `vim.fn.jobstart()`
- **AND** pass `NVIM_SOCKET_PATH` and workspace root as environment/arguments

#### Scenario: Sidecar stops with Gemini terminal session
- **WHEN** the Gemini terminal session is closed or killed
- **THEN** neph SHALL send SIGTERM to the companion sidecar process

#### Scenario: Sidecar respawns on crash
- **WHEN** the companion sidecar process exits unexpectedly
- **AND** the Gemini terminal session is still active
- **THEN** neph SHALL respawn the companion sidecar after a brief delay

### Requirement: Missing sidecar script notification

The companion module SHALL notify the user when the sidecar script is not found, rather than failing silently.

#### Scenario: Companion script not built

- **WHEN** `companion.start_sidecar()` is called
- **AND** `tools/gemini/dist/companion.js` does not exist
- **THEN** the system SHALL call `vim.notify("Neph: Gemini companion not built — run :NephTools install gemini", ERROR)`
- **AND** SHALL return nil without starting a job

#### Scenario: Companion script exists

- **WHEN** `companion.start_sidecar()` is called
- **AND** `tools/gemini/dist/companion.js` exists
- **THEN** no error notification SHALL be shown
- **AND** the sidecar SHALL start normally

### Requirement: Sidecar respawn with exponential backoff

The companion sidecar SHALL retry with exponential backoff and a retry cap instead of retrying indefinitely at a fixed interval.

#### Scenario: First respawn uses 2s delay

- **WHEN** the sidecar exits with non-zero code for the first time
- **AND** `vim.g.gemini_active` is set
- **THEN** the respawn SHALL be scheduled after 2000ms

#### Scenario: Subsequent respawns double the delay

- **WHEN** the sidecar exits with non-zero code for the Nth time
- **AND** N is 2 or 3
- **THEN** the respawn SHALL be scheduled after `2000 * 2^(N-1)` ms

#### Scenario: Respawn stops after 3 attempts

- **WHEN** the sidecar has failed 3 times
- **THEN** no further respawn SHALL be attempted
- **AND** the system SHALL call `vim.notify("Neph: Gemini companion failed to start after 3 attempts", ERROR)`

#### Scenario: Successful start resets retry counter

- **WHEN** the sidecar starts successfully (exits with code 0 or stays running)
- **THEN** the retry counter SHALL be reset to 0

### Requirement: HTTP request body size limit

The companion HTTP server SHALL reject requests with bodies exceeding 1MB.

#### Scenario: Request body exceeds limit

- **WHEN** an HTTP request body exceeds 1MB (1,048,576 bytes)
- **THEN** the server SHALL respond with HTTP 413 (Payload Too Large)
- **AND** SHALL destroy the request stream

#### Scenario: Request body within limit

- **WHEN** an HTTP request body is within 1MB
- **THEN** the request SHALL be processed normally
