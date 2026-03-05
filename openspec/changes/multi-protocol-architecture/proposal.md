## Why

Current architecture uses a Python subprocess shim with blocking shell commands and msgpack serialization, limiting testability, extensibility, and integration patterns. Research into amp.nvim (pure Lua WebSocket), claudecode.nvim (MCP protocol), claude-code.nvim (terminal wrapper), Amp toolboxes (stdin/stdout executables), and Claude Code hooks (shell scripts at lifecycle events) reveals multiple viable patterns for agent-editor integration. We need a clean-slate architecture that supports multiple protocols while maximizing testability, composability, and graceful degradation.

## What Changes

- **BREAKING**: Complete architectural redesign - no backward compatibility with existing plugin (pre-1.0, no users)
- **New**: Pure Lua API layer (`lua/neph/api/`) as the single source of truth for all file operations
- **New**: Protocol adapters as thin translation layers (WebSocket, RPC, Script) with graceful fallback
- **New**: Node client library (`@neph/client`) using `@neovim/node-client` for direct RPC
- **New**: Quality-focused testing: unit (pure Lua, fast), integration (real protocols), e2e (real agents, minimal)
- **New**: Lifecycle hooks system for extensibility at agent boundaries
- **Removed**: Python shim subprocess model - replaced by direct RPC or optional script protocol
- **Removed**: pi.ts extension override pattern - replaced by Lua registry with protocol adapters
- **Removed**: All migration complexity - clean break enables clean design

## Capabilities

### New Capabilities

- `lua-api-layer`: Pure Lua API for all file operations - single source of truth, fully testable
- `node-client`: TypeScript client library for direct RPC (primary integration pattern)
- `protocol-registry`: Clean protocol adapter interface with graceful degradation
- `lifecycle-hooks`: Extensibility at session and tool boundaries
- `testing-strategy`: Quality-focused tests (unit: fast feedback, integration: real behavior, e2e: user flows)

### Modified Capabilities

None - this is a clean-slate redesign with no backward compatibility constraints.

## Impact

**Code Changes:**
- New directory structure: `lua/neph/api/`, `lua/neph/protocols/`, `lua/neph/hooks/`
- Replace `tools/core/shim.py` subprocess model with direct RPC
- Refactor `tools/pi/pi.ts` to use `@neph/client` for RPC communication
- Add `tools/client/` for Node client library package
- Simplify to 2 core protocols: RPC (primary), Script (optional for shell-based agents)
- Clean test organization: `tests/unit/`, `tests/integration/`, `tests/e2e/`

**APIs:**
- **BREAKING**: Public API (`lua/neph/api.lua`) completely redesigned - focus on simplicity
- **BREAKING**: Agent configuration schema changes - `protocol` field replaces implicit subprocess
- **BREAKING**: No tool override pattern - tools are Lua functions with protocol adapters

**Dependencies:**
- Add `@neovim/node-client` to Node dependencies (primary protocol)
- Remove Python shim dependencies (uv, msgpack-rpc) - Python optional for script protocol only
- Add `vitest` for integration testing with headless Neovim

**Systems:**
- Default protocol is RPC (direct Neovim connection)
- Script protocol optional for shell-based agents (Amp toolbox style)
- WebSocket protocol deferred to future if streaming events are needed
- Clean failure modes: protocol unavailable → clear error, suggest alternatives
