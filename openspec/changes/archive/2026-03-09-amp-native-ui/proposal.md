## Why

The current integration with the Amp coding agent is limited to a one-way terminal-based communication for basic turn-taking and a command-line-based `review` workflow for file mutations. This creates a disjointed experience where agent status, notifications, and interactive prompts are buried in the agent's terminal output rather than being integrated into Neovim's native UI. By establishing a persistent side-channel bridge (similar to the Pi and OpenCode integrations), we can provide real-time status updates, native Neovim notifications, and interactive approval prompts, making Amp feel like a native editor companion.

## What Changes

- Update `tools/amp/neph-plugin.ts` to use a persistent `NephClient` connection instead of the fire-and-forget `nephRun` CLI.
- Implement Amp SDK hooks for `agent.start` and `agent.end` to push real-time status updates (`amp_running`) to Neovim via the side channel.
- Intercept and wrap the `ctx.ui` object provided by the Amp SDK to redirect `notify`, `confirm`, and `input` calls to native Neovim UI elements (`vim.notify`, `vim.ui.select`, `vim.ui.input`).
- Update `lua/neph/agents/amp.lua` to ensure the agent environment is correctly configured for the new persistent bridge (setting `PLUGINS=all`).
- Implement a `neph:prompt` listener in the Amp plugin to allow sending prompts directly from Neovim buffers to the active Amp thread.

## Capabilities

### New Capabilities
- `amp-native-ui`: Persistent bridge between Amp agent events/hooks and Neovim UI elements.

### Modified Capabilities
- `agent-client-sdk`: Ensure `NephClient` supports the persistent connection requirements for the Amp bridge.
- `rpc-dispatch`: Ensure Neovim's UI RPC endpoints correctly handle requests from the Amp companion.

## Impact

- `tools/amp/neph-plugin.ts` (major refactor to persistent model)
- `lua/neph/agents/amp.lua` (configuration updates)
- `tools/lib/neph-client.ts` (shared library usage)
- User statusline (new `amp_running` indicator)
