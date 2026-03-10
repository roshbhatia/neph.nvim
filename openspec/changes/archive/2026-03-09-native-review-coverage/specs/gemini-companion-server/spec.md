## MODIFIED Requirements

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
