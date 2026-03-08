## REMOVED Requirements

### Requirement: Send adapter interface
**Reason:** Replaced by bus-based routing. Session.send now checks `agent.type == "extension"` and routes through `neph.internal.bus` automatically. The `send_adapter` field on AgentDef is removed.
**Migration:** Remove `send_adapter` from custom agent definitions. Set `type = "extension"` on agents that need push-based prompt delivery. The bus handles routing.

### Requirement: neph inject-prompt command
**Reason:** No longer needed. Prompts are delivered via `vim.rpcnotify` through the bus, not via vim.g polling. The `neph_pending_prompt` global is removed entirely.
**Migration:** Extension agents receive prompts via the `neph:prompt` notification on their persistent connection.

### Requirement: Pi extension consumes pending prompts
**Reason:** Replaced by notification listener. Pi receives prompts via `NephClient.onPrompt()` callback, not by polling `vim.g.neph_pending_prompt`.
**Migration:** Use `NephClient` from `tools/lib/neph-client.ts`.

## MODIFIED Requirements

### Requirement: Session send dispatches by agent type
Session send SHALL dispatch through agent type. Extension agents (`type = "extension"`) SHALL have prompts routed through `neph.internal.bus`. Terminal and hook agents SHALL use the default chansend/wezterm CLI path. No per-agent `send_adapter` functions exist.

#### Scenario: Extension agent prompt via bus
- **WHEN** agent "pi" has `type = "extension"` and is registered on the bus
- **AND** `session.send("pi", "fix the bug", {submit = true})` is called
- **THEN** the prompt SHALL be delivered via `bus.send_prompt("pi", "fix the bug", {submit = true})`
- **AND** no chansend fallback SHALL execute

#### Scenario: Extension agent not connected falls through to terminal
- **WHEN** agent "pi" has `type = "extension"` but is NOT registered on the bus
- **AND** `session.send("pi", "fix the bug", {submit = true})` is called
- **THEN** the prompt SHALL fall through to the default chansend/wezterm path

#### Scenario: Terminal agent sends via chansend
- **WHEN** agent "goose" has no `type` field (terminal agent)
- **AND** `session.send("goose", "hello", {submit = true})` is called
- **THEN** the text SHALL be delivered via `vim.fn.chansend(chan, text .. "\n")`

#### Scenario: Hook agent sends via chansend
- **WHEN** agent "claude" has `type = "hook"`
- **AND** `session.send("claude", "hello", {submit = true})` is called
- **THEN** the text SHALL be delivered via the default terminal path (chansend or wezterm CLI)
