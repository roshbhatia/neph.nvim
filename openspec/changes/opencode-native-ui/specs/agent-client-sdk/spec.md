## MODIFIED Requirements

### Requirement: Prompt notification listener
`NephClient` SHALL provide an `onPrompt(callback)` method that fires when Neovim sends a `neph:prompt` notification.

#### Scenario: Prompt received via notification
- **WHEN** Neovim sends `vim.rpcnotify(channel, "neph:prompt", "fix the bug
")`
- **THEN** the `onPrompt` callback SHALL fire with `"fix the bug
"`
- **AND** this SHALL work for both `pi` and `opencode` persistent bridges
