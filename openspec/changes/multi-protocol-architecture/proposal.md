## Why

Current architecture uses a Python subprocess shim with blocking shell commands and msgpack serialization, limiting testability, extensibility, and integration patterns. Research into amp.nvim (pure Lua WebSocket), claudecode.nvim (MCP protocol), claude-code.nvim (terminal wrapper), Amp toolboxes (stdin/stdout executables), and Claude Code hooks (shell scripts at lifecycle events) reveals multiple viable patterns for agent-editor integration. We need an architecture that supports multiple protocols (WebSocket for streaming, scripts for shell agents, direct RPC for native clients) while maximizing testability through pure Lua APIs and thin language clients.

## What Changes

- **New**: Pure Lua API layer (`lua/neph/api/`) exposing write, edit, delete, read operations independent of protocol
- **New**: WebSocket server option in Lua using `vim.loop` for event-driven streaming (file changes, diagnostics, selections)
- **New**: Script-based tool protocol (Amp toolbox-style) with stdin/stdout communication and lifecycle hooks
- **New**: Node client library (`@neph/client`) using `@neovim/node-client` for direct RPC communication
- **New**: Comprehensive testing pyramid: 70% unit tests (plenary.nvim), 25% integration tests (vitest + headless nvim), 5% e2e tests (real agents)
- **Modified**: Existing Python shim becomes one of multiple language client options, not the sole integration point
- **Modified**: Tool registration moves from pi.ts extension overrides to protocol-agnostic registration in Lua
- **Breaking**: Public API signatures remain compatible but internal tool protocol changes require agent-specific adapters

## Capabilities

### New Capabilities

- `lua-api-layer`: Pure Lua API for all file operations (write, edit, delete, read) with protocol-agnostic interface
- `websocket-protocol`: WebSocket server implementation using vim.loop with lockfile discovery and event streaming
- `script-tool-protocol`: Executable-based tool system with stdin/stdout communication (describe/execute actions)
- `lifecycle-hooks`: Event-driven hooks at agent lifecycle points (session_start, pre_tool, post_tool, session_end)
- `node-client`: TypeScript client library for direct RPC communication with Neovim
- `protocol-negotiation`: Auto-detection and registration of available protocols per agent
- `testing-infrastructure`: Comprehensive test suite with mocked Neovim instances and protocol adapters

### Modified Capabilities

- `tool-registration`: Tool definitions move from pi.ts extension to protocol-agnostic Lua registry with adapter pattern
- `shim-protocol`: Python shim becomes optional protocol adapter, not mandatory subprocess dependency

## Impact

**Code Changes:**
- New directory structure: `lua/neph/api/`, `lua/neph/protocols/`, `lua/neph/hooks/`
- Refactor `tools/pi/pi.ts` to use `@neph/client` instead of shim.py subprocess
- Add `tools/client/` for Node client library package
- Create `lua/neph/protocols/{websocket,script,rpc}.lua` protocol adapters
- Add `tests/unit/`, `tests/integration/`, `tests/e2e/` test organization

**APIs:**
- Public API (`lua/neph/api.lua`) remains backward compatible
- Internal tool protocol changes require migration guide for custom agents
- New protocol registration API for agent definitions

**Dependencies:**
- Add `@neovim/node-client` to Node dependencies
- Add `vitest` for integration testing
- Python shim dependencies become optional if not using Python protocol

**Systems:**
- Agents can choose protocol: WebSocket (streaming), Script (shell), RPC (native), or Shim (legacy)
- Existing pi agent continues working but can migrate to direct RPC
- Opens path for amp, claude-code, goose integration patterns
