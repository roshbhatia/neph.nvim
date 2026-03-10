## ADDED Requirements

### Requirement: Amp SDK Persistent Bridge
The system SHALL provide a persistent bridge plugin for Amp (`tools/amp/neph-plugin.ts`) that uses the Amp SDK to intercept agent events and tool calls via a persistent `NephClient` connection.

#### Scenario: Amp session start
- **WHEN** Amp starts a session
- **THEN** the bridge plugin SHALL connect to Neovim via `NephClient`
- **AND** register as the `amp` agent
- **AND** set `vim.g.amp_active` to `true`

#### Scenario: Real-time turn status
- **WHEN** Amp triggers an `agent.start` event
- **THEN** the bridge SHALL call `setStatus("amp_running", "true")` in Neovim
- **AND** when `agent.end` is triggered, it SHALL call `unsetStatus("amp_running")`

#### Scenario: Intercepted Review
- **WHEN** Amp attempts to call `edit_file`, `create_file`, or `apply_patch`
- **THEN** the bridge SHALL intercept the call
- **AND** trigger a `review` in Neovim using `NephClient.review`
- **AND** resolve the tool call with the user's decision (accept/reject)

#### Scenario: Native UI Bridging
- **WHEN** any Amp plugin calls `ctx.ui.notify`, `ctx.ui.confirm`, or `ctx.ui.input`
- **THEN** the bridge SHALL redirect these calls to Neovim via `NephClient`'s UI interaction methods
- **AND** return the user's response from Neovim back to the Amp plugin

#### Scenario: Native prompt receiving
- **WHEN** Neovim sends a `neph:prompt` notification to the Amp bridge
- **THEN** the bridge SHALL forward the prompt to Amp using `thread.append` (or equivalent SDK call)
