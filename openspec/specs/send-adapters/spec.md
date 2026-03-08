## ADDED Requirements

### Requirement: Send adapter interface
Session send SHALL dispatch through an adapter layer. Each agent MAY have a custom adapter. The default adapter SHALL use `vim.fn.chansend()` directly with the terminal's job channel ID. All adapter send operations SHALL be non-blocking — adapters that invoke external processes SHALL use `vim.fn.jobstart()` instead of `vim.fn.system()`.

#### Scenario: Default terminal adapter sends via chansend
- **GIVEN** an agent with no custom adapter (e.g., claude, goose)
- **WHEN** `session.send(termname, text, {submit=true})` is called
- **THEN** the text is delivered via `vim.fn.chansend(chan, text)` followed by `vim.fn.chansend(chan, "\n")`
- **AND** the text arrives intact regardless of terminal column width

#### Scenario: WezTerm adapter sends via async CLI
- **GIVEN** an agent running in a WezTerm pane
- **WHEN** `session.send(termname, text, {submit=true})` is called
- **THEN** the text is delivered via `vim.fn.jobstart({"wezterm", "cli", "send-text", ...})`
- **AND** the Neovim event loop is not blocked during the send
- **AND** send errors are reported via `vim.notify()` in the on_exit callback

#### Scenario: Pi adapter sends via programmatic API
- **GIVEN** pi is the active agent with a running extension
- **WHEN** `session.send("pi", text, {submit=true})` is called
- **THEN** the text is delivered via `neph inject-prompt <text>` which sets `vim.g.neph_pending_prompt`
- **AND** the pi extension detects this and calls `pi.sendUserMessage(text)`
- **AND** the text bypasses the terminal pty entirely

#### Scenario: Pi adapter falls back to terminal if extension not running
- **GIVEN** pi is active but `vim.g.pi_active` is not set (extension not loaded)
- **WHEN** `session.send("pi", text, {submit=true})` is called
- **THEN** delivery falls back to the default terminal adapter

### Requirement: neph inject-prompt command
The neph CLI SHALL support an `inject-prompt` command that sets `vim.g.neph_pending_prompt` to the provided text via neovim RPC. This is a fire-and-forget command used by the Lua side to signal the pi extension.

#### Scenario: inject-prompt sets vim.g
- **WHEN** `neph inject-prompt "fix the bug"` is executed
- **THEN** `vim.g.neph_pending_prompt` is set to `"fix the bug"` in the connected neovim instance

### Requirement: Pi extension consumes pending prompts
The pi extension SHALL poll or watch for `vim.g.neph_pending_prompt`. When a value is detected, it SHALL call `pi.sendUserMessage(value)` and clear the global.

#### Scenario: Extension picks up pending prompt
- **GIVEN** `vim.g.neph_pending_prompt` is set to `"fix the bug"`
- **WHEN** the pi extension checks for pending prompts
- **THEN** it calls `pi.sendUserMessage("fix the bug")`
- **AND** clears `vim.g.neph_pending_prompt` to nil
