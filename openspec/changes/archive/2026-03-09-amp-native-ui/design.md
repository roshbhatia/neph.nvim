## Context

The Amp coding agent provides a TypeScript-based plugin API that runs within a long-lived process (using the Bun runtime). This API allows plugins to intercept tool calls, subscribe to agent lifecycle events, and interact with the user via a `ctx.ui` object. Currently, our Amp integration uses a fire-and-forget CLI-based approach for reviews, which is stateless and doesn't support rich, bi-directional interaction. By establishing a persistent socket connection via `NephClient`, we can bridge Amp's rich plugin hooks directly to Neovim's UI and status systems.

## Goals / Non-Goals

**Goals:**
- Replace the CLI-based `nephRun` calls in the Amp plugin with a persistent `NephClient` instance.
- Map Amp agent lifecycle events (`agent.start`, `agent.end`) to Neovim global status variables (`vim.g.amp_running`).
- Bridge Amp's `ctx.ui` calls (`notify`, `confirm`, `input`) to native Neovim UI functions (`vim.notify`, `vim.ui.select`, `vim.ui.input`).
- Listen for `neph:prompt` notifications from Neovim to support sending prompts directly to the Amp agent thread.
- Maintain the existing `review` functionality for file mutations, but transition it to use the `NephClient.review` method for better integration.

**Non-Goals:**
- Rewriting the Amp CLI itself; we are only enhancing the Neovim companion plugin.
- Supporting non-standard or custom UI elements beyond what Neovim's `vim.ui` and `vim.notify` provide.

## Decisions

**1. Persistent Side-Channel Connection:**
We will initialize a `NephClient` instance within the `session.start` hook of the Amp plugin. This connection will stay active for the duration of the Amp session, allowing for low-latency status updates and interactive prompts.
*Rationale:* Provides a unified communication model consistent with our Pi and OpenCode integrations.

**2. Intercepting and Wrapping `ctx.ui`:**
We will use the Amp SDK's `session.start` (or equivalent global context access) to wrap the `ctx.ui` methods. This ensures that any plugin running within Amp (including third-party ones) will automatically use Neovim's UI when bridged.
*Rationale:* Maximum leverage of existing Amp plugin ecosystem with zero upstream changes required.

**3. Tool Call Interception for Reviews:**
We will maintain the `tool.call` hook for `edit_file`, `create_file`, and `apply_patch`. Instead of spawning the `neph` CLI, we will use the `NephClient.review` method, which correctly handles asynchronous user responses over the socket.
*Rationale:* Faster and more reliable than spawning multiple CLI processes.

**4. Handling the Bun Runtime:**
Since Amp plugins run in Bun, we will ensure `NephClient` (which is standard Node TypeScript) remains compatible. Bun's high compatibility with Node's `net` and `process` modules should make this seamless.

## Risks / Trade-offs

- **[Risk] Bun Compatibility**: While Bun aims for 100% Node compatibility, subtle differences in socket handling or process environment could lead to connection issues.
  - **Mitigation**: Perform early testing within the Amp/Bun environment and use standard, robust Node APIs in `NephClient`.
- **[Risk] Concurrency**: Multiple plugins or simultaneous turn-ends could lead to race conditions in status variable updates.
  - **Mitigation**: Use serial execution or clear state ownership within `NephClient` status methods.
- **[Risk] Experimental API**: The Amp plugin API is explicitly marked as WIP and experimental.
  - **Mitigation**: Stick to documented hooks and maintain the required experimental header comments.
