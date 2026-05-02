## ADDED Requirements

### Requirement: Peer adapter registry

neph SHALL expose a `neph.peers` registry that maps a peer kind (e.g. `"claudecode"`, `"opencode"`) to an adapter module implementing the peer adapter contract. Adapters SHALL be loaded lazily by `peers.resolve(kind)` so that absent peer plugins do not raise during neph setup.

#### Scenario: Resolve known adapter

- **WHEN** `require("neph.peers").resolve("claudecode")` is called
- **AND** `lua/neph/peers/claudecode.lua` exists
- **THEN** the call SHALL return the adapter table
- **AND** SHALL NOT raise even if `claudecode.nvim` itself is not installed

#### Scenario: Resolve unknown kind

- **WHEN** `require("neph.peers").resolve("nonexistent")` is called
- **THEN** the call SHALL return `nil`
- **AND** an error message SHALL be logged at debug level via `log.debug("peers", ...)`

### Requirement: Peer adapter availability check

Each peer adapter SHALL implement `is_available()` returning `boolean, string|nil`. The boolean indicates whether the underlying peer plugin is installed and usable; the string carries a human-readable reason when unavailable.

#### Scenario: claudecode plugin present

- **WHEN** `pcall(require, "claudecode")` returns `true`
- **AND** the user calls the claudecode adapter's `is_available()`
- **THEN** it SHALL return `true, nil`

#### Scenario: claudecode plugin absent

- **WHEN** `pcall(require, "claudecode")` returns `false`
- **AND** the user calls the claudecode adapter's `is_available()`
- **THEN** it SHALL return `false, "claudecode.nvim is not installed"`

### Requirement: Peer adapter session lifecycle

Each peer adapter SHALL expose: `open(agent, opts)`, `send(agent, text, opts)`, `kill(agent)`, `is_visible(agent)`, `focus(agent)`, `hide(agent)`. `open(agent, opts)` SHALL return a `term_data`-shaped table compatible with what backends return, so `session.lua` can store it without special-casing.

#### Scenario: open returns term_data shape

- **WHEN** the claudecode adapter's `open(agent, {})` is called
- **AND** the peer plugin successfully starts a Claude Code session
- **THEN** the returned table SHALL include the keys `{ ready = boolean, peer = "claudecode", ... }`
- **AND** `session.lua` SHALL store it in the same slot used for backend-managed terminals

#### Scenario: send routes to peer

- **WHEN** the user invokes `<leader>ja` for a peer agent and the input prompt is submitted
- **AND** `session.send` resolves the agent's adapter
- **THEN** the adapter's `send(agent, text, {submit = true})` SHALL be called
- **AND** the text SHALL be delivered through the peer plugin's send API (not via chansend)

#### Scenario: kill tears down peer session

- **WHEN** the user invokes the kill command for a peer agent
- **THEN** the adapter's `kill(agent)` SHALL stop the peer plugin's session for this agent
- **AND** subsequent `is_visible(agent)` calls SHALL return `false`

### Requirement: Session dispatch routes peer agents to adapters

`session.open(agent_name, opts)` SHALL inspect `agent.type`. When the type is `"peer"`, the session module SHALL skip the configured backend and instead call `peers.resolve(agent.peer.kind).open(agent, opts)`. Hook, terminal, and extension agents SHALL continue to use their existing dispatch paths.

#### Scenario: Peer agent skips backend

- **WHEN** an agent with `type = "peer"` and `peer = { kind = "claudecode" }` is opened
- **THEN** the configured backend's `open()` SHALL NOT be called
- **AND** `peers.resolve("claudecode").open(agent, opts)` SHALL be called instead

#### Scenario: Hook agent uses backend (unchanged)

- **WHEN** an agent with `type = "hook"` is opened
- **THEN** the configured backend's `open()` SHALL be called as before
- **AND** no peer adapter SHALL be invoked

### Requirement: claudecode adapter overrides openDiff to neph review queue

When a `claudecode` peer agent has `peer.override_diff = true`, the adapter SHALL replace `claudecode.tools.handlers.openDiff` (after `claudecode.setup()` runs) with a handler that enqueues a review through `neph.internal.review_queue` and resolves the deferred MCP response based on the user's accept/reject decision.

#### Scenario: openDiff routes to review queue

- **WHEN** Claude Code calls the `openDiff` MCP tool over the websocket
- **AND** the active claudecode peer agent has `peer.override_diff = true`
- **THEN** the override handler SHALL extract `oldFile`, `newFile`, `proposed`, `description`
- **AND** SHALL call `review_queue.enqueue({ source = "claudecode", file = newFile, ... })`
- **AND** SHALL defer the MCP response until the review resolves

#### Scenario: User accepts in neph review UI

- **WHEN** a deferred openDiff is pending
- **AND** the user accepts via `ga` / `gA` / `gs` in neph's review UI
- **THEN** the adapter SHALL resolve the MCP response with `{ accepted = true, content = <accepted-content> }`

#### Scenario: User rejects in neph review UI

- **WHEN** a deferred openDiff is pending
- **AND** the user rejects via `gr` / `gR`
- **THEN** the adapter SHALL resolve the MCP response with `{ accepted = false }`

#### Scenario: Override disabled

- **WHEN** a claudecode peer agent has `peer.override_diff = false`
- **THEN** the adapter SHALL NOT replace `openDiff`
- **AND** claudecode.nvim's native vimdiff handler SHALL fire as usual

### Requirement: opencode adapter delegates prompts and lifecycle

The opencode adapter SHALL delegate session start/stop to `require("opencode")`, route `session.send` text through `opencode.prompt()`, and report `is_available()` based on `pcall(require, "opencode")`.

#### Scenario: opencode adapter sends via prompt API

- **WHEN** the user submits a prompt for an opencode peer agent
- **AND** the opencode adapter's `send(agent, text, opts)` is called
- **THEN** it SHALL call `require("opencode").prompt(text, opts)`
- **AND** SHALL NOT spawn a separate terminal

#### Scenario: opencode adapter reports unavailable when plugin missing

- **WHEN** `opencode.nvim` is not installed
- **AND** `peers.resolve("opencode").is_available()` is called
- **THEN** it SHALL return `false, "opencode.nvim is not installed"`
- **AND** the picker SHALL display the agent as unavailable rather than failing on open
