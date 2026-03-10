## Why

The current integration with the `opencode` coding agent uses a collection of standalone tool scripts (`write.ts`, `edit.ts`) that interact with Neovim via the `neph` CLI. While functional, it lacks a persistent connection for real-time status updates and requires manual CLI orchestration for every UI interaction. By moving to a persistent bridge model (similar to the `pi` integration) and adding UI commands to the `neph` CLI, we can provide a cohesive, "native" feel for OpenCode interactions, including real-time statusline updates and interactive approval prompts.

## What Changes

- Add `ui-select`, `ui-input`, and `ui-notify` commands to the `neph` CLI to support tool-based UI interactions.
- Create a persistent Neph-Opencode bridge extension (`tools/opencode/opencode.ts`) using the OpenCode SDK.
- Update `lua/neph/agents/opencode.lua` to treat `opencode` as an `extension` type and symlink the new persistent bridge.
- Map OpenCode lifecycle events (`session.busy`, `session.idle`) to Neovim status variables via the persistent side channel.
- Implement a global OpenCode plugin that intercepts sensitive tools (like `shell`) to trigger native Neovim UI approval prompts.

## Capabilities

### New Capabilities
- `opencode-native-ui`: Persistent bridge between OpenCode agent events/hooks and Neovim UI elements.
- `cli-ui-commands`: `neph` CLI commands for triggering interactive Neovim UI prompts from standalone scripts.

### Modified Capabilities
- `agent-client-sdk`: Ensure `NephClient` effectively handles the `neph:prompt` notification for OpenCode to support the `neph.api.ask` workflow.
- `neph-cli`: Add support for the new UI bridge RPC methods.

## Impact

- `tools/neph-cli/src/index.ts` (new commands)
- `tools/opencode/opencode.ts` (new persistent bridge)
- `lua/neph/agents/opencode.lua` (type change and new symlinks)
- `tools/lib/neph-run.ts` (new UI helper functions)
