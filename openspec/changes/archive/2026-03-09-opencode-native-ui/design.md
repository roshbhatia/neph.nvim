## Context

Currently, `opencode` is integrated via individual tool scripts that spawn the `neph` CLI for specific tasks like `review`. This model is stateless between tool calls and doesn't support real-time agent status or generic UI prompts outside of those tools. OpenCode's SDK supports a plugin system that can intercept tool execution and subscribe to lifecycle events. We want to leverage this to create a persistent bridge that makes OpenCode feel like a first-class citizen in Neovim, similar to our `pi` integration.

## Goals / Non-Goals

**Goals:**
- Implement `ui-select`, `ui-input`, and `ui-notify` commands in the `neph` CLI to support the new UI RPC endpoints.
- Create a persistent bridge plugin (`tools/opencode/opencode.ts`) that maintains a `NephClient` connection while the agent is running.
- Bridge OpenCode `session.busy` and `session.idle` events to Neovim status variables (`vim.g.opencode_running`).
- Intercept the `shell` tool using the SDK's `tool.execute.before` hook to trigger a native Neovim approval prompt.
- Allow OpenCode to receive prompts directly from Neovim via the side channel (`neph:prompt`).

**Non-Goals:**
- Rewriting the existing `write.ts` and `edit.ts` tools to use the persistent connection (they will continue to use the CLI for now to maintain simplicity, but can benefit from the new `ui-*` commands).
- Implementing a full SSE client in Lua (we will use the TS side channel for all events).

## Decisions

**1. CLI Command Parity:**
We will add `ui-select`, `ui-input`, and `ui-notify` to the `neph` CLI. These will follow the pattern used by `review`: create a `requestId`, send the RPC, and wait for a corresponding notification from Neovim before exiting and printing the result. This ensures that even standalone scripts (not just the persistent bridge) can use native UI.

**2. Persistent Bridge Location:**
The new bridge will be at `tools/opencode/opencode.ts`. It will be configured as a global OpenCode plugin. OpenCode loads plugins from `~/.config/opencode/plugin/`. We will update our agent definition to symlink our bridge there.

**3. Intercepting the Shell Tool:**
OpenCode's SDK provides a `tool.execute.before` hook. We will use this to check if the tool is `shell`. If so, we'll call `neph.uiSelect` to ask the user for permission in Neovim. If the user rejects, we'll throw an error in the hook to abort the execution.

**4. Mapping Status:**
We will map:
- `session.busy` -> `setStatus("opencode_running", "true")`
- `session.idle` -> `unsetStatus("opencode_running")`
This allows for a real-time "thinking" indicator in the statusline.

## Risks / Trade-offs

- **[Risk] CLI Overhead**: Spawning the `neph` CLI for every UI prompt in a script might be slightly slower than a persistent socket.
  - **Mitigation**: For interactive tools we control, the delay is negligible compared to user reaction time. For the agent itself, the persistent bridge handles events without spawning.
- **[Risk] Plugin Path Conflicts**: If the user already has a `neph-bridge.ts` in their OpenCode config.
  - **Mitigation**: We will use a unique name like `neph-companion.ts` and document the requirement.
