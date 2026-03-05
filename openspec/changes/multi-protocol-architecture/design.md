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

### 5. Pi Integration via Extension (Hook, Don't Replace)

**Decision:** Hook into pi's tool execution flow, don't replace tools:

```typescript
// tools/pi/extensions/neph.ts
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  
  // Hook BEFORE tool executes (intercept)
  pi.on("tool_call", async (event, ctx) => {
    if (!["write_file", "edit_file"].includes(event.toolName)) return;
    
    // Let tool execute first, get the result
    const original = event.toolName === "edit_file" 
      ? await readFile(event.input.path)
      : null;
    
    // Tool will execute, then we review
    return undefined; // don't block yet
  });
  
  // Hook AFTER tool executes (review)
  pi.on("tool_result", async (event, ctx) => {
    if (!["write_file", "edit_file"].includes(event.toolName)) return;
    
    // Show diff of what tool just did
    const result = await ctx.nvim.lua(`
      return require("neph.api.review").show_diff(
        "${event.input.path}",
        "${original || ''}",
        "${event.result.content}"
      )
    `);
    
    if (result.decision === "Reject") {
      // Revert the change
      await writeFile(event.input.path, original);
      return { modify: { error: "User rejected change" } };
    }
    
    if (result.decision === "Edit") {
      // Update with user's edited version
      await writeFile(event.input.path, result.content);
      return { modify: { content: result.content } };
    }
    
    // Accept - let original result stand
  });
}
```

**Benefits:**
- Uses pi's existing write_file/edit_file tools (tested, maintained by pi team)
- We just wrap with review UX
- Can accept/reject/edit after seeing what tool did
- No need to reimplement tool logic

**Rationale:**
- Pi's tools already handle edge cases (file permissions, encoding, etc.)
- OpenCode, Claude, Gemini, Amp also have their own tools
- Our job: add review UX, not replace tools

**Alternatives considered:**
- ❌ **Replace tools entirely**: Reimplementing tool logic, maintenance burden
- ❌ **Override tool definitions**: Bypasses agent's tool system, fragile

### 6. Integration Patterns Per Agent

**Decision:** Support all 10 agents with appropriate integration for each:

#### RPC Integration (Native API Support)

**Pi**
```typescript
// Hook tool_result to review after execution
pi.on("tool_result", async (event, ctx) => {
  if (["write_file", "edit_file"].includes(event.toolName)) {
    const result = await ctx.nvim.lua(`review.show_diff(...)`);
    // Accept/Reject/Edit based on user choice
  }
});
```

**OpenCode**
```typescript
// OpenCode also supports extensions, same pattern as pi
opencode.on("tool_result", async (event, ctx) => {
  // Same review flow as pi
});
```

**Cursor**
```typescript
// cursor-agent likely supports similar extension model
// Check cursor-agent docs for hook points
cursor.on("tool_result", async (event, ctx) => {
  // Review flow if cursor supports extensions
});
```

#### Terminal Integration (CLI-Only)

**Claude**
```lua
-- Anthropic Claude CLI
terminal.send("claude", context.expand(prompt))
```

**Gemini**
```lua
-- Google Gemini CLI
terminal.send("gemini", context.expand(prompt))
```

**Goose**
```lua
-- Block/Square Hole Goose
terminal.send("goose", context.expand(prompt))
```

**Copilot**
```lua
-- GitHub Copilot CLI
terminal.send("copilot", context.expand(prompt))
```

#### Hybrid / TBD (Check Capabilities)

**Amp**
```lua
-- Sourcegraph Amp with --ide flag
-- May support RPC/extensions, currently using terminal
-- Watch: https://github.com/sourcegraph/amp
if amp.supports_extensions then
  -- Use RPC integration
else
  terminal.send("amp", context.expand(prompt))
end
```

**Crush**
```lua
-- Unknown agent - needs research
-- Default to terminal integration
terminal.send("crush", context.expand(prompt))
```

**Codex**
```lua
-- Unknown agent - needs research  
-- Default to terminal integration
terminal.send("codex", context.expand(prompt))
```

**Agent Classification:**
- **RPC-capable**: pi, opencode, cursor (likely)
- **Terminal-only**: claude, gemini, goose, copilot
- **Needs research**: amp (has --ide flag), crush, codex

**Rationale:**
- Use RPC when agent exposes extension API
- Terminal for CLI-only agents
- Easy to upgrade when agents add RPC support
- Configuration declares integration mode explicitly

**Key insight:**
We're not building one universal protocol - we're building **integration patterns** that match each agent's capabilities.

**Alternatives considered:**
- ❌ **Force all agents to one protocol**: Limits what we can do
- ❌ **Build MCP server**: Wrong abstraction, we're integrating with agents, not serving them
- ❌ **Only support RPC agents**: Excludes useful CLI tools

### 7. Terminal Integration (Simple Text Sending)

**Decision:** For CLI agents (claude, gemini), just send text reliably:

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
- Terminal integration doesn't intercept agent's UX
- No diff review (CLI agents handle their own prompting)
- Just reliable text sending + context expansion

**Rationale:**
- Claude, Gemini already have their own review flows
- Trying to intercept CLI output is fragile
- Keep it simple: send input, let agent control UX

**Alternatives considered:**
- ❌ **Parse CLI output**: Breaks with agent updates
- ❌ **Build wrapper per agent**: Maintenance nightmare

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

### 8. Testing Strategy - Real Behavior

**Decision:** Agent configuration is Lua code, not config files:

```lua
-- lua/neph/internal/agents.lua (shipped with plugin)
return {
  -- RPC Integration (agents with extension APIs)
  pi = {
    integration = "rpc",
    command = "pi --continue",
    rpc = {
      extension = "tools/pi/extensions/neph.ts",
      socket = "~/.pi/socket",
    },
  },
  
  opencode = {
    integration = "rpc",
    command = "opencode --continue",
    rpc = {
      extension = "tools/opencode/extensions/neph.ts",
      socket = "~/.opencode/socket",
    },
  },
  
  cursor = {
    integration = "rpc",  -- if cursor-agent supports extensions
    command = "cursor-agent",
    rpc = {
      extension = "tools/cursor/extensions/neph.ts",
      socket = "~/.cursor/socket",
    },
  },
  
  -- Terminal Integration (CLI-only agents)
  claude = {
    integration = "terminal",
    command = "claude --permission-mode plan",
    terminal = { multiplexer = "wezterm" },
  },
  
  gemini = {
    integration = "terminal",
    command = "gemini",
    terminal = { multiplexer = "wezterm" },
  },
  
  goose = {
    integration = "terminal",
    command = "goose",
    terminal = { multiplexer = "wezterm" },
  },
  
  copilot = {
    integration = "terminal",
    command = "copilot --allow-all-paths",
    terminal = { multiplexer = "wezterm" },
  },
  
  -- Hybrid / TBD (needs research)
  amp = {
    integration = "terminal",  -- may support RPC in future
    command = "amp --ide",
    terminal = { multiplexer = "wezterm" },
  },
  
  crush = {
    integration = "terminal",  -- unknown agent, default to terminal
    command = "crush",
    terminal = { multiplexer = "wezterm" },
  },
  
  codex = {
    integration = "terminal",  -- unknown agent, default to terminal
    command = "codex",
    terminal = { multiplexer = "wezterm" },
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
    claude = {
      command = "claude --model sonnet-4",  -- override command
    },
  },
})
```

**Rationale:**
- Configuration is versioned with plugin
- LSP provides completion for config
- Easy to document (it's just Lua)
- User overrides merge with defaults
- Clear which agents use RPC vs Terminal
- Unknown agents default to terminal (safe fallback)

**Alternatives considered:**
- ❌ **JSON/YAML files**: No validation, no completion
- ❌ **Env vars**: Hard to document, no structure
- ❌ **Auto-detection**: Hidden complexity, hard to debug

### 9. Configuration is Code (Not Files)

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
4. Test with manual Lua API calls

### Phase 2: RPC Integration (Pi, OpenCode, Cursor)
1. Create pi extension using `ExtensionAPI`
2. Hook `tool_result` event to call Lua review API
3. Use `ctx.nvim.lua()` for RPC calls
4. Integration test with headless Neovim
5. Create opencode extension (same pattern)
6. Research cursor-agent extension API, implement if available

### Phase 3: Terminal Integration (All CLI Agents)
1. Simplify terminal sending code
2. Keep context expansion (+file, +selection)
3. Test with claude, gemini, goose, copilot
4. Default configuration for amp, crush, codex

### Phase 4: Research & Upgrade TBD Agents
1. Research amp --ide mode for RPC capabilities
2. Research crush and codex agents
3. Upgrade to RPC integration if available
4. Document findings in agent registry

### Phase 5: Documentation
1. Agent configuration guide (all 10 agents)
2. Adding new agents guide
3. Extension installation guide (RPC agents)
4. Testing guide (unit/integration/e2e)

**Agent Priority:**
- **Phase 2**: pi (primary), opencode (known RPC)
- **Phase 3**: claude, gemini, goose, copilot (CLI)
- **Phase 4**: cursor (likely RPC), amp (research), crush (research), codex (research)

## Open Questions

1. **Should we auto-start pi if not running?**
   - Leaning toward: No, user controls agent lifecycle

2. **How to handle pi socket discovery?**
   - Leaning toward: Check `$PI_SOCKET`, then `~/.pi/socket`, then error

3. **Should terminal integration support diff review?**
   - Leaning toward: No, CLI agents control their own UX

4. **What about agents that support both modes?**
   - Leaning toward: Config declares one mode, no auto-switching
