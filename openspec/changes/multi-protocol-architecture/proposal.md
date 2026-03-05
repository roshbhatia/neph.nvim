## Why

Current architecture sends text to agents via terminal/multiplexer, even for agents that support native RPC APIs (pi, opencode). Diff review flow uses fragile subprocess + msgpack serialization. We need stable, native integration that uses agent RPC APIs when available, with clear fallback to terminal for CLI-only agents.

## What Changes

- **BREAKING**: Complete redesign - two integration modes (RPC + Terminal) replace subprocess shim
- **New**: Pure Lua API for file operations and diff review - single source of truth
- **New**: RPC integration for pi/opencode using their native extension APIs
- **New**: Pi extension using `ExtensionAPI` - calls Lua via `ctx.nvim` (built-in RPC connection)
- **New**: Simplified terminal integration for CLI agents (goose, claude)
- **Removed**: Python shim subprocess model
- **Removed**: pi.ts tool override pattern - replaced by pi extension using native hooks
- **Removed**: Complex protocol negotiation - config explicitly declares integration mode

## Capabilities

### New Capabilities

- `lua-api-layer`: Pure Lua API for file ops + diff review - testable, single source of truth
- `rpc-integration`: Native integration with pi/opencode using their RPC APIs (ctx.nvim)
- `terminal-integration`: Simplified text sending for CLI agents with context expansion
- `agent-configuration`: Explicit integration mode declaration per agent

### Modified Capabilities

None - clean-slate redesign.

## Impact

**Code Changes:**
- New: `lua/neph/api/` - Pure Lua API (write, edit, delete, read, review)
- New: `tools/pi/extensions/neph.ts` - Pi extension using `ExtensionAPI`
- New: `lua/neph/integrations/rpc.lua` - RPC mode handler
- Simplified: `lua/neph/integrations/terminal.lua` - Terminal mode handler
- Remove: `tools/core/shim.py` - No longer needed
- Update: `lua/neph/internal/agents.lua` - Config declares integration mode

**Integration Modes:**

**RPC Mode (pi, opencode):**
```typescript
// pi extension hooks tool_call
pi.on("tool_call", async (event, ctx) => {
  const result = await ctx.nvim.lua(`
    return require("neph.api.review").show_diff(...)
  `);
  if (result.decision === "Reject") {
    return { block: true };
  }
});
```

**Terminal Mode (goose, claude):**
```lua
-- Send text to terminal via multiplexer
terminal.send(agent, context.expand(prompt))
```

**Configuration:**
```lua
agents = {
  pi = { integration = "rpc", rpc = { extension = "..." } },
  goose = { integration = "terminal", command = "goose session start" },
}
```

**APIs:**
- **BREAKING**: No public API compatibility (pre-1.0, clean break)
- New: `require("neph.api.review").show_diff(path, old, new)` - diff review as Lua function
- New: Agent config schema with explicit `integration` mode

**Dependencies:**
- pi extension requires pi coding-agent (users already have this)
- Terminal integration requires no new deps
- Testing: plenary (Lua), vitest (TypeScript integration tests)

**Systems:**
- RPC integration: Uses agent's native RPC API, no subprocess
- Terminal integration: Direct text sending, no subprocess
- Diff review: Pure Lua function, works from both modes
- Configuration: Explicit mode declaration, no auto-detection
