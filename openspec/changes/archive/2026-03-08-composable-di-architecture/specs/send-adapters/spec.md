## MODIFIED Requirements

### Requirement: Send adapter interface
Session send SHALL dispatch through an adapter layer. Each agent MAY have a custom adapter via the `send_adapter` field on its injected `AgentDef`. The default adapter SHALL use `vim.fn.chansend()` directly with the terminal's job channel ID. All adapter send operations SHALL be non-blocking — adapters that invoke external processes SHALL use `vim.fn.jobstart()` instead of `vim.fn.system()`.

#### Scenario: Default terminal adapter sends via chansend
- **WHEN** an agent with no `send_adapter` field is active
- **AND** `session.send(termname, text, {submit=true})` is called
- **THEN** the text is delivered via `vim.fn.chansend(chan, text)` followed by `vim.fn.chansend(chan, "\n")`
- **AND** the text arrives intact regardless of terminal column width

#### Scenario: WezTerm adapter sends via async CLI
- **WHEN** an agent running in a WezTerm pane is active
- **AND** `session.send(termname, text, {submit=true})` is called
- **THEN** the text is delivered via `vim.fn.jobstart({"wezterm", "cli", "send-text", ...})`
- **AND** the Neovim event loop is not blocked during the send
- **AND** send errors are reported via `vim.notify()` in the on_exit callback

#### Scenario: Custom send_adapter on injected AgentDef
- **WHEN** an agent's `AgentDef` includes a `send_adapter` function
- **AND** `session.send(termname, text, opts)` is called
- **THEN** the `send_adapter` function is called with `(td, text, opts)`
- **AND** if it returns truthy, the default send is skipped
- **AND** if it returns falsy, the default send path is used as fallback

#### Scenario: Pi adapter sends via programmatic API
- **WHEN** pi is the active agent with `send_adapter` defined in its `AgentDef`
- **AND** `session.send("pi", text, {submit=true})` is called
- **THEN** the text is delivered via `vim.g.neph_pending_prompt`
- **AND** the pi extension detects this and calls `pi.sendUserMessage(text)`

#### Scenario: Pi adapter falls back to terminal if extension not running
- **WHEN** pi is active but `vim.g.pi_active` is not set (extension not loaded)
- **AND** `session.send("pi", text, {submit=true})` is called
- **THEN** delivery falls back to the default terminal adapter
