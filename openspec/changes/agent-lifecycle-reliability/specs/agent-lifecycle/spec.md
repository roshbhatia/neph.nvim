## ADDED Requirements

### Requirement: Ready pattern detection for terminal agents

`AgentDef` SHALL accept an optional `ready_pattern` field (Lua string pattern). When a terminal agent is spawned, the backend SHALL watch the terminal output and match each line against `ready_pattern`. The agent's `term_data.ready` flag SHALL be set to `true` when a match is found.

#### Scenario: Agent with ready_pattern becomes ready on match

- **WHEN** an agent defines `ready_pattern = "^%s*>"`
- **AND** the agent's terminal output contains a line matching `> `
- **THEN** `term_data.ready` SHALL be set to `true`

#### Scenario: Agent without ready_pattern is immediately ready

- **WHEN** an agent does not define a `ready_pattern` field
- **AND** the backend returns a `term_data` from `open()`
- **THEN** `term_data.ready` SHALL be `true` immediately

#### Scenario: Ready detection times out

- **WHEN** an agent defines `ready_pattern`
- **AND** no matching output appears within 30 seconds
- **THEN** `term_data.ready` SHALL be set to `true` (fail-open)
- **AND** a debug log entry SHALL be written

### Requirement: Snacks backend output watching

The snacks backend SHALL hook the terminal job's `on_stdout` callback to monitor output for ready pattern detection.

#### Scenario: Snacks detects ready pattern in terminal output

- **WHEN** a terminal is opened via the snacks backend
- **AND** the agent has a `ready_pattern`
- **THEN** the backend SHALL register an `on_stdout` callback
- **AND** the callback SHALL match each output line against the pattern
- **AND** `term_data.ready` SHALL be set to `true` on first match

#### Scenario: Snacks stops watching after ready

- **WHEN** the ready pattern has been matched
- **THEN** the `on_stdout` callback SHALL stop pattern matching (no further overhead)

### Requirement: WezTerm backend output watching

The WezTerm backend SHALL poll `wezterm cli get-text --pane-id <id>` to detect the ready pattern.

#### Scenario: WezTerm detects ready pattern via polling

- **WHEN** a pane is opened via the WezTerm backend
- **AND** the agent has a `ready_pattern`
- **THEN** the backend SHALL poll `wezterm cli get-text` at 200ms intervals
- **AND** the poll SHALL match each line of output against the pattern
- **AND** `term_data.ready` SHALL be set to `true` on first match

#### Scenario: WezTerm stops polling after ready or timeout

- **WHEN** the ready pattern has been matched or 30 seconds have elapsed
- **THEN** the polling timer SHALL be stopped and closed

### Requirement: Ready queue for pending text

`session.lua` SHALL maintain a per-terminal queue of text to send. When `ensure_active_and_send` is called and the terminal is not yet ready, the text SHALL be queued. When the terminal becomes ready, all queued text SHALL be drained in order via `M.send()`.

#### Scenario: Text queued while agent is loading

- **WHEN** `ensure_active_and_send("claude", "fix the bug")` is called
- **AND** claude's terminal exists but `term_data.ready` is `false`
- **THEN** the text SHALL be added to claude's pending queue
- **AND** `M.send()` SHALL NOT be called immediately

#### Scenario: Queue drained on ready

- **WHEN** claude's `term_data.ready` becomes `true`
- **AND** claude's pending queue contains `["fix the bug", "also check tests"]`
- **THEN** `M.send("claude", "fix the bug", {submit=true})` SHALL be called first
- **AND** `M.send("claude", "also check tests", {submit=true})` SHALL be called second
- **AND** the queue SHALL be empty after draining

#### Scenario: Queue discarded on kill

- **WHEN** `kill_session("claude")` is called
- **AND** claude has pending queued text
- **THEN** the queue SHALL be discarded

### Requirement: FocusGained health check

`session.lua` SHALL check terminal health on `FocusGained` in addition to `CursorHold`.

#### Scenario: Dead pane detected on FocusGained

- **WHEN** the user returns to Neovim (FocusGained fires)
- **AND** a WezTerm pane for "goose" has been killed externally
- **THEN** session SHALL detect the dead pane via `backend.is_visible()`
- **AND** `vim.g.goose_active` SHALL be cleared

#### Scenario: FocusGained with healthy panes

- **WHEN** FocusGained fires
- **AND** all tracked panes are still alive
- **THEN** no state changes SHALL occur

### Requirement: Gate stderr warning on socket failure

`neph-cli gate` SHALL write a visible warning to stderr when it cannot connect to the Neovim socket.

#### Scenario: NVIM_SOCKET_PATH is stale

- **WHEN** `gate --agent claude` is invoked
- **AND** the socket at `NVIM_SOCKET_PATH` does not exist or is unreachable
- **THEN** neph-cli SHALL write a warning to stderr containing the socket path
- **AND** neph-cli SHALL exit with code 0 (fail-open)

#### Scenario: NVIM_SOCKET_PATH is not set

- **WHEN** `gate --agent claude` is invoked
- **AND** `NVIM_SOCKET_PATH` is not set in the environment
- **AND** `discoverNvimSocket()` returns null
- **THEN** neph-cli SHALL write a warning to stderr indicating no socket was found
- **AND** neph-cli SHALL exit with code 0 (fail-open)

### Requirement: Unified vim.g state management

`session.lua` SHALL be the sole writer of `vim.g.{name}_active` for ALL agent types. `bus.lua` SHALL NOT modify `vim.g` state directly.

#### Scenario: Terminal agent state set on open

- **WHEN** `session.open("goose")` succeeds
- **THEN** `vim.g.goose_active` SHALL be set to `true`

#### Scenario: Extension agent state set on open

- **WHEN** `session.open("pi")` succeeds
- **AND** pi is an extension agent
- **THEN** `vim.g.pi_active` SHALL be set to `true`

#### Scenario: State cleared on kill for all types

- **WHEN** `session.kill_session("goose")` is called
- **THEN** `vim.g.goose_active` SHALL be set to `nil`

#### Scenario: State cleared when health check detects dead pane

- **WHEN** CursorHold or FocusGained fires
- **AND** the pane for "goose" is dead
- **THEN** `vim.g.goose_active` SHALL be set to `nil`

#### Scenario: Bus registration does not touch vim.g

- **WHEN** `bus.register({name = "pi", channel = 5})` is called
- **THEN** `vim.g.pi_active` SHALL NOT be modified by bus.lua
