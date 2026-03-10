## ADDED Requirements

### Requirement: NephClient connection management
`tools/lib/neph-client.ts` SHALL export a `NephClient` class that connects to Neovim's Unix socket using the `neovim` npm package and maintains a persistent connection.

#### Scenario: Connect using NVIM_SOCKET_PATH
- **WHEN** `new NephClient()` is created and `connect()` is called
- **AND** `NVIM_SOCKET_PATH` is set in the environment
- **THEN** the client SHALL connect to that socket path
- **AND** the connection SHALL remain open until `disconnect()` is called

#### Scenario: Connect fails gracefully
- **WHEN** `connect()` is called but the socket path does not exist
- **THEN** `connect()` SHALL reject with a descriptive error

### Requirement: Agent registration
`NephClient` SHALL provide a `register(agentName)` method that registers the agent with the bus, passing its RPC channel ID.

#### Scenario: Register sends channel ID
- **WHEN** `client.register("pi")` is called
- **THEN** the client SHALL call `executeLua` with `bus.register({name = "pi", channel = <own_channel_id>})`
- **AND** the promise SHALL resolve on success

### Requirement: Prompt notification listener
`NephClient` SHALL provide an `onPrompt(callback)` method that fires when Neovim sends a `neph:prompt` notification.

#### Scenario: Prompt received via notification
- **WHEN** Neovim sends `vim.rpcnotify(channel, "neph:prompt", "fix the bug\n")`
- **THEN** the `onPrompt` callback SHALL fire with `"fix the bug\n"`

### Requirement: Status helpers
`NephClient` SHALL provide `setStatus(name, value)` and `unsetStatus(name)` methods that call the existing `status.set` and `status.unset` RPC methods.

#### Scenario: Set status variable
- **WHEN** `client.setStatus("pi_running", "true")` is called
- **THEN** `vim.g.pi_running` SHALL be set to `"true"` in Neovim

#### Scenario: Unset status variable
- **WHEN** `client.unsetStatus("pi_running")` is called
- **THEN** `vim.g.pi_running` SHALL be set to `nil` in Neovim

### Requirement: Review via RPC
`NephClient` SHALL provide a `review(filePath, content)` method that opens an interactive review in Neovim and returns the user's decision by waiting for an asynchronous RPC notification.

#### Scenario: Review returns envelope
- **WHEN** `client.review("/tmp/foo.ts", "new content")` is called
- **THEN** Neovim SHALL open a vimdiff review tab
- **AND** the client SHALL wait for a `neph:review_done` notification containing the result
- **AND** the promise SHALL resolve with a `ReviewEnvelope` when the notification is received

### Requirement: UI interaction methods
`NephClient` SHALL provide generic `uiSelect`, `uiInput`, and `uiNotify` methods that invoke their respective Neovim RPCs and, for interactive methods, wait for a notification response.

#### Scenario: uiSelect resolves on notification
- **WHEN** `client.uiSelect("Title", ["A", "B"])` is called
- **THEN** the client SHALL invoke `ui.select`
- **AND** wait for a corresponding `neph:ui_response` notification before resolving the returned promise

#### Scenario: uiInput resolves on notification
- **WHEN** `client.uiInput("Prompt", "Default")` is called
- **THEN** the client SHALL invoke `ui.input`
- **AND** wait for a corresponding `neph:ui_response` notification before resolving the returned promise

#### Scenario: uiNotify is fire-and-forget
- **WHEN** `client.uiNotify("Message", "info")` is called
- **THEN** the client SHALL invoke `ui.notify` and resolve the promise immediately without waiting for a notification

### Requirement: Checktime helper
`NephClient` SHALL provide a `checktime()` method that triggers buffer reload in Neovim.

#### Scenario: Checktime reloads buffers
- **WHEN** `client.checktime()` is called
- **THEN** Neovim SHALL execute `:checktime`

### Requirement: Auto-reconnect
`NephClient` SHALL automatically reconnect if the socket connection is lost, using exponential backoff (100ms initial, 5s cap).

#### Scenario: Reconnect after socket loss
- **WHEN** the Neovim socket closes unexpectedly
- **THEN** the client SHALL attempt to reconnect with exponential backoff
- **AND** on successful reconnect, the client SHALL re-register with the bus

#### Scenario: Reconnect stops on explicit disconnect
- **WHEN** `client.disconnect()` is called
- **THEN** no further reconnect attempts SHALL be made
