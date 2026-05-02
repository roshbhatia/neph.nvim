## MODIFIED Requirements

### Requirement: Agent type enum

`AgentDef.type` SHALL accept one of `{"hook", "terminal", "extension", "peer"}`. The `peer` value indicates that session lifecycle (open, send, kill, focus) is delegated to a third-party Neovim plugin via a peer adapter resolved by `agent.peer.kind`.

#### Scenario: Peer agent validates with kind

- **WHEN** an agent is registered with `type = "peer"` and `peer = { kind = "claudecode" }`
- **THEN** `contracts.validate_agent` SHALL accept the definition without error

#### Scenario: Peer agent missing kind is rejected

- **WHEN** an agent is registered with `type = "peer"` but `peer` is `nil` or `peer.kind` is missing
- **THEN** `contracts.validate_agent` SHALL raise an error containing the agent name and the message `peer.kind is required`

#### Scenario: Hook/terminal/extension agents unaffected

- **WHEN** an agent is registered with `type = "hook"`, `"terminal"`, or `"extension"`
- **THEN** validation behavior SHALL be unchanged from the previous spec

## ADDED Requirements

### Requirement: Peer agents skip backend launch

When `session.open()` resolves an agent with `type = "peer"`, the configured backend SHALL NOT be invoked. Instead, the peer adapter resolved via `peers.resolve(agent.peer.kind)` SHALL be invoked. The session module SHALL still record the resulting `term_data` so subsequent `send`/`kill`/`is_visible` calls find it.

#### Scenario: Backend's open() not called for peer

- **WHEN** `session.open("claude-peer", {})` is invoked
- **AND** `claude-peer` has `type = "peer"`, `peer = { kind = "claudecode" }`
- **THEN** the configured backend's `open()` SHALL NOT be called
- **AND** `peers.resolve("claudecode").open(agent, opts)` SHALL be called
- **AND** the returned `term_data` SHALL be stored in the session registry under `"claude-peer"`

#### Scenario: Send dispatches to peer adapter

- **WHEN** `session.send("claude-peer", "fix +diagnostics", { submit = true })` is invoked
- **AND** the peer adapter is registered for the agent
- **THEN** `peers.resolve("claudecode").send(agent, "fix +diagnostics", { submit = true })` SHALL be called
- **AND** no chansend or wezterm CLI fallback SHALL execute

#### Scenario: Peer agent unavailable falls through with notification

- **WHEN** `session.open("claude-peer", {})` is invoked
- **AND** `peers.resolve("claudecode").is_available()` returns `false, "claudecode.nvim is not installed"`
- **THEN** the session module SHALL emit a single notification per session containing the unavailability reason
- **AND** SHALL NOT crash; subsequent calls for the same agent SHALL no-op until the plugin is installed
