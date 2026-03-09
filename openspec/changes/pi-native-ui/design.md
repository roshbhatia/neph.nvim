## Context

The `pi` coding agent framework supports extensions, which run inside the agent process (often spawned in the background). These extensions need to interact with the user (e.g., asking for confirmation before running a shell command, selecting an option from a list, prompting for text input). They do this via a generic `ctx.ui` interface (`ExtensionUIContext`). 

Currently, `neph.nvim` starts `pi` but doesn't natively handle these UI requests, leaving interactions either unsupported or constrained to the raw terminal output. By bridging these requests over our existing RPC channel (which already powers our `review` feature), we can present these UI elements directly inside Neovim using its native capabilities (like `vim.ui.select`, `vim.ui.input`, and `vim.notify`).

## Goals / Non-Goals

**Goals:**
- Intercept `ctx.ui` calls (`select`, `input`, `confirm`, `notify`) in the `pi` extension using the SDK's `session_start` hook.
- Transmit these UI requests to Neovim over the existing Unix socket RPC using `NephClient`.
- Render the UI in Neovim using standard APIs (`vim.ui.select`, `vim.ui.input`, `vim.notify`).
- Ensure the Neovim-side handlers send responses back, and the `NephClient` resolves the original Promises correctly.

**Non-Goals:**
- Implementing a completely new TUI or UI layer inside Neovim (we will strictly rely on `vim.ui` and `vim.notify`).
- Refactoring the main `neph-cli` transport for other agents; this change is focused on `NephClient` (`tools/lib/neph-client.ts`) and the `pi` extension.

## Decisions

**1. Intercepting the `ctx.ui` Object:**
Instead of modifying the core `pi-mono` agent, we will use our existing `neph` extension (`tools/pi/pi.ts`) to wrap the `ctx.ui` object provided in the `session_start` hook. This ensures maximum compatibility and requires zero changes upstream.
*Alternatives considered:* Trying to act as the primary UI client for `pi`, but that would bypass `pi`'s native TUI modes when users run it standalone.

**2. Asynchronous RPC Handling in NephClient:**
The current `NephClient.review` method uses a somewhat brittle pattern where it expects `executeLua` to return a synchronous result, while Neovim actually spins up a vimdiff tab and returns immediately, relying on a file to be written. We will update `NephClient` to correctly use `executeLua` in a fire-and-forget manner (or wait for the prompt to open) and then resolve the promise *only* when a corresponding `neph:<action>_response` notification is received over the socket.
*Alternatives considered:* Keeping the synchronous assumption, which would freeze the Neovim UI thread since `executeLua` blocks until the Lua function returns.

**3. Lua API Modules:**
We will introduce `lua/neph/api/ui.lua` with functions like `select(params)` and `input(params)`. These will invoke the `vim.ui.*` functions and, upon callback execution, use `vim.rpcnotify` to send the user's choice back to the client.

## Risks / Trade-offs

- **[Risk] Multiple simultaneous UI requests:** If an agent spams UI requests, `vim.ui.*` might overlay multiple prompts confusingly.
  - **Mitigation:** Rely on Neovim's natural behavior for `vim.ui` (which often stacks floating windows or command-line prompts). If it becomes an issue, we can implement a queue in `api/ui.lua`.
- **[Risk] Timeout or closed connections:** If the user ignores the prompt or the socket disconnects, the agent might hang indefinitely waiting for a promise resolution.
  - **Mitigation:** Implement timeouts on the TypeScript side for interactive prompts, throwing an error or resolving with `undefined` to allow the agent to proceed or abort.
