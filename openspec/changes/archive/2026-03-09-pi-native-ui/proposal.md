## Why

The current integration with the `pi` coding agent runs in the background but relies on the terminal for UI interactions (like `select`, `input`, or `notify`). This makes the experience feel disconnected from Neovim, where users expect these interactions to happen through familiar, native interfaces (like `vim.ui.select` or `vim.ui.input`). By bridging the `pi-mono` SDK's generic UI capabilities (`ExtensionUIContext`) to Neovim via RPC, we can give the agent a fully "native" feel, improving usability and cohesion.

## What Changes

- Add generic UI bridging to the RPC layer (`neph.rpc`), exposing methods for `ui.select`, `ui.input`, and `ui.notify`.
- Implement Lua handlers for these generic UI methods to call `vim.ui.select`, `vim.ui.input`, and `vim.notify` respectively, handling asynchronous user responses.
- Update `NephClient` (`tools/lib/neph-client.ts`) to fix the asynchronous handling of RPC methods that require waiting for a notification from Neovim (like `review` and the new UI prompts).
- Update the `pi` extension (`tools/pi/pi.ts`) to intercept the `session_start` hook and wrap the `ctx.ui` object provided by the `pi-mono` SDK. The wrapper will redirect calls to `select`, `confirm`, `input`, and `notify` to Neovim via `NephClient`.

## Capabilities

### New Capabilities
- `native-ui-rpc`: Bridge generic UI requests (select, input, notify) from agents to Neovim UI elements via RPC.
- `pi-native-ui`: Wrap the Pi SDK's `ExtensionUIContext` to map `ctx.ui` calls to the Neph RPC bridge.

### Modified Capabilities
- `rpc-dispatch`: Add the new `ui.select`, `ui.input`, and `ui.notify` endpoints to the dispatcher.
- `agent-client-sdk`: Update `NephClient` to support async UI requests via RPC, ensuring `review` and UI methods properly wait for Neovim's asynchronous callbacks/notifications before resolving.

## Impact

- `lua/neph/rpc.lua` and new modules in `lua/neph/api/ui/`
- `tools/lib/neph-client.ts`
- `tools/pi/pi.ts`
- Any future extensions running inside the `pi` agent will automatically inherit this native UI capability.