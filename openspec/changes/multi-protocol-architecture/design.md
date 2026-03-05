## Context

**Current State:**
- Python subprocess (shim.py) sends text to terminal via WezTerm/multiplexer
- No native integration with agent RPC APIs (pi, opencode support this)
- Diff review flow works but is fragile (subprocess, msgpack serialization)
- Testing requires complex mocking of subprocess communication

**Research Findings:**
1. **pi coding-agent**: RPC extension API with `ctx.ui.select()`, `ctx.ui.input()`, `ctx.ui.editor()`, `ctx.ui.setStatus()`
2. **opencode**: Also supports RPC interface for native integration
3. **Amp toolboxes**: Shell executables for one-shot tools (no persistent connection needed)
4. **Our UX**: Diff review flow is the pattern we want - just needs to be stable and work reliably

**Key Insight:**
We have **two integration patterns**:
1. **Agents with RPC APIs** (pi, opencode) → Use their native API, not terminal text
2. **CLI-only agents** (goose, claude, etc.) → Terminal text via multiplexer

**Goal:**
Make integration layers stable, obvious, and easy to configure. KISS principle.

**Constraints:**
- Neovim ≥ 0.10 required
- Quality over minimalism - use whatever dependencies make sense
- Must support both RPC-capable agents AND terminal-only agents
- Diff review UX is the pattern - make it bulletproof

## Goals / Non-Goals

**Goals:**
- **Two integration modes**: RPC (for pi, opencode) + Terminal (for CLI agents)
- **Stable diff review**: Works reliably, no subprocess fragility
- **Easy configuration**: Agent declares its integration mode, rest is automatic
- **Extensible**: New agents are easy to add, integration pattern is obvious
- **Native when possible**: Use agent's RPC API if available (better than terminal text)

**Non-Goals:**
- Generic protocol system (just need RPC + Terminal, that's it)
- WebSocket server (don't need editor-as-server pattern)
- Script protocol as separate thing (it's just "no persistent connection" terminal mode)
- Migration from old code (clean break, no users)

## Decisions

### 1. Two Integration Modes (KISS)

**Decision:** Support exactly two modes:

**Mode 1: RPC Integration** (for pi, opencode, future agents with APIs)
```typescript
// tools/pi-client/src/index.ts
import { PiClient } from "@mariozechner/pi-coding-agent/client";

const pi = await PiClient.connect();

// Native API calls, no terminal text needed
await pi.ui.select("Review change?", ["Accept", "Reject"]);
await pi.ui.input("Enter commit message");
await pi.ui.editor("Edit prompt", initialText);
```

**Mode 2: Terminal Integration** (for goose, claude, other CLI agents)
```lua
-- lua/neph/integrations/terminal.lua
local terminal = require("neph.terminal")

-- Send text to agent's terminal via multiplexer
terminal.send(agent, "Please write hello.py\n")
```

**Rationale:**
- RPC is better when available (native UI, structured data, no parsing)
- Terminal is fallback for CLI-only agents
- No need for 4 protocols - just these two patterns

**Alternatives considered:**
- ❌ **WebSocket**: Overkill, RPC does everything we need
- ❌ **Universal protocol**: Agents have different APIs, embrace it
- ❌ **Only terminal**: Wastes RPC capabilities of pi/opencode

### 2. Agent Configuration Declares Integration Mode

**Decision:** Agent config explicitly declares how to integrate:

```lua
-- lua/neph/internal/agents.lua
agents = {
  pi = {
    integration = "rpc",
    rpc = {
      client = "tools/pi-client/dist/index.js",
      socket = "~/.pi/socket",  -- or auto-discover
    },
  },
  
  goose = {
    integration = "terminal",
    terminal = {
      command = "goose session start",
      multiplexer = "wezterm",  -- or native, tmux
    },
  },
}
```

**Rationale:**
- Configuration is explicit - no magic auto-detection
- Easy to add new agents - just copy pattern
- Clear which integration mode is used

**Alternatives considered:**
- ❌ **Auto-detect**: Hidden complexity, hard to debug when wrong
- ❌ **Implicit defaults**: User doesn't know what's happening

### 3. Pure Lua API as Single Source of Truth

**Decision:** All file operations go through pure Lua API, regardless of integration mode:

```
RPC Integration:              Terminal Integration:
  pi client                     terminal send
      ↓                              ↓
  lua/neph/api/write.lua ← lua/neph/api/write.lua
      ↓                              ↓
  filesystem                    filesystem
```

**What this means:**
- RPC client calls Lua API via Neovim RPC
- Terminal integration also calls Lua API (on behalf of agent)
- Tests only need to mock Lua API layer
- All validation, error handling in one place

**Example - pi diff review:**
```typescript
// pi extension calls Neovim RPC
const choice = await nvim.lua(`
  return require("neph.api.review").show_diff(${path}, ${original}, ${modified})
`);

// Lua API handles the diff display, returns choice
// No subprocess, no msgpack serialization
```

**Rationale:**
- Single code path for file operations
- Testable in isolation
- No duplication between integration modes

**Alternatives considered:**
- ❌ **Different APIs per mode**: Duplication, drift, bugs
- ❌ **No API layer**: Logic scattered across integrations

### 4. Diff Review as Lua Function

**Decision:** Diff review is a pure Lua function that returns a decision:

```lua
-- lua/neph/api/review.lua
function M.show_diff(path, original, modified)
  -- Open diff in splits
  local left_buf = create_buffer(original)
  local right_buf = create_buffer(modified)
  
  -- Show picker (Snacks.picker.select)
  local choice = vim.ui.select({"Accept", "Reject", "Edit"})
  
  -- Return structured result
  return {
    decision = choice,
    content = get_final_content(),
  }
end
```

**Called from pi extension:**
```typescript
// tools/pi/extensions/neph.ts
pi.on("tool_call", async (event, ctx) => {
  if (event.toolName !== "write_file") return;
  
  const result = await ctx.nvim.lua(`
    return require("neph.api.review").show_diff(
      ${event.input.path},
      ${original},
      ${event.input.content}
    )
  `);
  
  if (result.decision === "Accept") {
    // Continue with write
  } else {
    return { block: true };
  }
});
```

**Rationale:**
- Pure Lua function - testable with plenary
- No subprocess, no temp files, no notification polling
- Works from RPC or terminal integration

**Alternatives considered:**
- ❌ **Keep subprocess model**: Fragile, hard to test
- ❌ **Temp files + polling**: Current model, unnecessary complexity

### 5. Pi Integration via Extension (Native API)

**Decision:** Integrate with pi using its extension API properly:

```typescript
// tools/pi/extensions/neph.ts
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  
  // Hook into tool calls for diff review
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "write_file") return;
    
    // Call Lua API via ctx.nvim (Neovim RPC connection)
    const result = await ctx.nvim.lua(`
      return require("neph.api.review").show_diff(...)
    `);
    
    if (result.decision === "Reject") {
      return { block: true, reason: "User rejected change" };
    }
  });
  
  // Use pi's UI methods for prompts
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setStatus("neph", "Ready");
  });
}
```

**Benefits:**
- Uses pi's `ctx.nvim` (built-in Neovim RPC connection)
- Uses pi's `ctx.ui` methods (native dialogs)
- No subprocess spawning
- No intermediate shim layer

**Rationale:**
- This is how pi extensions are meant to work (see rpc-demo.ts example)
- Direct RPC connection already exists in pi's extension context
- Cleaner than spawning external process

**Alternatives considered:**
- ❌ **External process**: Adds latency, complexity
- ❌ **Override tools completely**: Bypasses pi's tool system

### 6. Terminal Integration for CLI Agents

**Decision:** For agents without RPC APIs, keep terminal integration simple:

```lua
-- lua/neph/integrations/terminal.lua
function M.send_prompt(agent_name, prompt)
  local agent = agents[agent_name]
  local backend = session.get_backend(agent)
  
  -- Expand context placeholders (+file, +selection, etc.)
  local expanded = context.expand(prompt)
  
  -- Send to terminal
  backend.send(expanded .. "\n")
end
```

**Key point:**
- Terminal integration doesn't need diff review (CLI agents control their own UX)
- Just need reliable text sending + context expansion
- Keep it simple

**Rationale:**
- CLI agents already have their own prompting/review flows
- Our job is just to send them the right input
- Don't try to intercept/modify their UX

**Alternatives considered:**
- ❌ **Try to intercept CLI output**: Fragile, breaks with agent updates
- ❌ **Build wrapper for every CLI agent**: Maintenance nightmare

### 7. Testing Strategy - Real Behavior

**Decision:** Test the actual integration, not mocked approximations:

**Unit tests (Lua with plenary):**
```lua
describe("api.review", function()
  it("shows diff and returns decision", function()
    local result = review.show_diff(path, "old", "new")
    assert.equals("Accept", result.decision)
  end)
end)
```

**Integration tests (TypeScript with real Neovim):**
```typescript
test("pi extension calls review API", async () => {
  const nvim = await spawnHeadlessNvim();
  loadPiExtension(nvim);
  
  // Trigger tool call
  await pi.tools.write_file("/tmp/test.txt", "content");
  
  // Verify Lua API was called
  const calls = await nvim.lua("return review_calls");
  expect(calls).toHaveLength(1);
});
```

**E2E tests (Real agents, minimal):**
```bash
# Start pi with neph extension
pi --extension tools/pi/extensions/neph.ts

# Send prompt that triggers file write
echo "Write hello.py" | pi

# Verify diff review was shown
# (manual verification or screenshot testing)
```

**Rationale:**
- Integration tests verify RPC connection works
- Unit tests verify Lua API logic
- E2E tests verify user experience
- Focus on "does it work" not "did we hit 70% coverage"

**Alternatives considered:**
- ❌ **Mock everything**: Tests pass but real integration breaks
- ❌ **Only e2e tests**: Too slow for development loop

### 8. Configuration is Code (Not Files)

**Decision:** Agent configuration is Lua code, not config files:

```lua
-- lua/neph/internal/agents.lua (shipped with plugin)
return {
  pi = {
    integration = "rpc",
    command = "pi",
    rpc = {
      extension = "tools/pi/extensions/neph.ts",
    },
  },
  
  goose = {
    integration = "terminal",
    command = "goose session start",
  },
}
```

**User overrides in setup():**
```lua
require("neph").setup({
  agents = {
    pi = {
      rpc = {
        socket = "~/custom/pi.sock",  -- override socket path
      },
    },
  },
})
```

**Rationale:**
- Configuration is versioned with plugin
- LSP provides completion for config
- Easy to document (it's just Lua)
- User overrides merge with defaults

**Alternatives considered:**
- ❌ **JSON/YAML files**: No validation, no completion
- ❌ **Env vars**: Hard to document, no structure

## Risks / Trade-offs

### Risk: pi extension needs pi to already be running
**Decision:** That's fine. User starts pi, loads extension. If pi isn't running, show clear error.

### Risk: Different integration modes for different agents
**Decision:** That's reality. Some agents have RPC, some don't. Configuration makes it explicit.

### Trade-off: Requires pi extension installation
**Decision:** Ship extension with plugin. User runs: `pi --extension ~/.local/share/nvim/site/pack/.../neph.nvim/tools/pi/extensions/neph.ts`

### Trade-off: Terminal integration is "dumber" than RPC
**Decision:** Correct. CLI agents control their own UX. We just send text. That's fine.

## Implementation Plan

### Phase 1: Pure Lua API
1. Extract file operations to `lua/neph/api/`
2. Implement diff review as pure Lua function
3. Unit test with plenary (no external deps)

### Phase 2: Pi RPC Integration
1. Create pi extension using `ExtensionAPI`
2. Hook `tool_call` event to call Lua review API
3. Use `ctx.nvim.lua()` for RPC calls
4. Integration test with headless Neovim

### Phase 3: Terminal Integration
1. Simplify terminal sending code
2. Keep context expansion (+file, +selection)
3. Test with goose/claude CLI agents

### Phase 4: Documentation
1. Agent configuration guide
2. Adding new agents guide
3. Extension installation guide

## Open Questions

1. **Should we auto-start pi if not running?**
   - Leaning toward: No, user controls agent lifecycle

2. **How to handle pi socket discovery?**
   - Leaning toward: Check `$PI_SOCKET`, then `~/.pi/socket`, then error

3. **Should terminal integration support diff review?**
   - Leaning toward: No, CLI agents control their own UX

4. **What about agents that support both modes?**
   - Leaning toward: Config declares one mode, no auto-switching
