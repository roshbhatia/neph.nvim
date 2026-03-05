## Context

**Current State:**
- Single Python subprocess shim (shim.py) is the only integration point
- Tools overridden in pi.ts extension via pi coding-agent hooks
- Blocking shell execution model limits concurrency
- Testing requires complex mocking of subprocess and msgpack protocol
- No event streaming capability (file changes, diagnostics must be polled)

**Research Findings:**
1. **amp.nvim** (Sourcegraph): Pure Lua WebSocket server using `vim.loop`, lockfile discovery at `~/.claude/ide/[port].lock`, event-driven architecture (file_changed, diagnostics_updated, selection_changed)
2. **claudecode.nvim** (Coder): WebSocket + MCP protocol (JSON-RPC 2.0), reverse-engineered VS Code extension, 12 MCP tools (openFile, openDiff, etc.)
3. **claude-code.nvim** (greggh): Simple terminal wrapper + file watching with plenary
4. **Amp toolboxes**: Executables in `$AMP_TOOLBOX` directories, stdin/stdout protocol with `describe` and `execute` actions, environment variables for context
5. **Claude Code hooks**: Shell commands at lifecycle events (SessionStart, PreToolUse, PostToolUse, etc.) with JSON input/output, permission decisions

**Constraints:**
- Must maintain backward compatibility with existing public API (`lua/neph/api.lua`)
- Cannot break existing pi agent workflow during migration
- Must work with Neovim ≥ 0.10, no external runtime dependencies beyond Node/Python for specific protocols
- snacks.nvim remains the only mandatory Lua dependency

## Goals / Non-Goals

**Goals:**
- **Multiple protocol support**: WebSocket (streaming), Script (shell executables), RPC (direct), Shim (legacy Python)
- **Pure Lua API layer**: All file operations (write, edit, delete, read) exposed as Lua functions, protocol-agnostic
- **Maximum testability**: 70% unit tests (plenary), 25% integration (vitest + headless nvim), 5% e2e (real agents)
- **Event-driven architecture**: Support streaming events (file changes, diagnostics, selections) via WebSocket
- **Gradual migration**: Existing agents continue working while new protocols become available
- **Protocol auto-detection**: Agents can advertise supported protocols, neph selects best available

**Non-Goals:**
- Implementing all MCP tools from claudecode.nvim (start with file operations only)
- Full WebSocket server with HTTP upgrade handshake (lockfile + raw socket sufficient for editor integration)
- Replacing all existing agents immediately (migration is opt-in)
- Supporting protocols beyond WebSocket, Script, RPC, Shim in initial implementation
- Building a generic MCP server (focus on neph-specific protocol needs)

## Decisions

### 1. Protocol Layering Architecture

**Decision:** Three-layer architecture:
```
┌─────────────────────────────────────────────────────────┐
│  Layer 3: Language Clients (Node, Python, Scripts)     │
│  - @neph/client (TypeScript + @neovim/node-client)     │
│  - shim.py (Python msgpack-rpc, legacy)                 │
│  - Executable scripts (stdin/stdout protocol)           │
└─────────────────────────────────────────────────────────┘
                          ↓ RPC / WebSocket / Stdio
┌─────────────────────────────────────────────────────────┐
│  Layer 2: Protocol Adapters (Lua)                      │
│  - lua/neph/protocols/rpc.lua (direct nvim RPC)        │
│  - lua/neph/protocols/websocket.lua (vim.loop server)  │
│  - lua/neph/protocols/script.lua (vim.fn.system)       │
│  - lua/neph/protocols/shim.lua (existing subprocess)   │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Pure Lua API (Protocol-Agnostic)             │
│  - lua/neph/api/write.lua                               │
│  - lua/neph/api/edit.lua                                │
│  - lua/neph/api/delete.lua                              │
│  - lua/neph/api/read.lua                                │
│  - lua/neph/api/events.lua (file changes, diagnostics) │
└─────────────────────────────────────────────────────────┘
```

**Rationale:**
- **Pure Lua API** enables comprehensive unit testing without external dependencies
- **Protocol adapters** isolate transport concerns, each testable independently
- **Language clients** can be thin wrappers around transport, minimal logic
- Follows amp.nvim pattern (Lua server) while supporting multiple transports

**Alternatives considered:**
- ❌ **Single protocol (WebSocket only)**: Would force all agents to WebSocket, breaks existing Python/Node workflows
- ❌ **Keep shim as sole integration**: Limits architecture exploration, no path to event streaming
- ❌ **Protocol logic in language clients**: Makes testing harder, duplicates validation across clients

### 2. WebSocket Implementation Strategy

**Decision:** Pure Lua WebSocket server using `vim.loop.new_tcp()`, lockfile at `~/.neph/sockets/[pid].lock` with port number.

**Rationale:**
- `vim.loop` provides non-blocking socket API built into Neovim
- Lockfile discovery pattern proven by amp.nvim (Sourcegraph uses this in production)
- No HTTP upgrade complexity needed for editor-agent communication
- JSON-RPC 2.0 format compatible with MCP tools if we expand scope later

**Implementation sketch:**
```lua
-- lua/neph/protocols/websocket.lua
local uv = vim.loop
local server = uv.new_tcp()
server:bind("127.0.0.1", 0) -- random port
local port = server:getsockname().port

-- Write lockfile
local lockfile = vim.fn.stdpath("data") .. "/neph/sockets/" .. vim.fn.getpid() .. ".lock"
vim.fn.writefile({ tostring(port) }, lockfile)

server:listen(128, function(err)
  local client = uv.new_tcp()
  server:accept(client)
  client:read_start(function(err, chunk)
    -- JSON-RPC 2.0 message handling
  end)
end)
```

**Alternatives considered:**
- ❌ **HTTP WebSocket with upgrade**: Overhead not needed for local socket communication
- ❌ **Unix domain socket**: Not cross-platform (Windows), lockfile + TCP port more portable
- ❌ **Named pipes**: Platform-specific, TCP sockets simpler

### 3. Script Protocol Design

**Decision:** Amp toolbox-style protocol with `NEPH_ACTION` environment variable and stdin/stdout JSON.

**Actions:**
- `describe`: Script outputs tool schema (JSON with `name`, `description`, `inputSchema`)
- `execute`: Script receives tool input via stdin, returns result via stdout

**Environment variables:**
- `NEPH_ACTION`: "describe" or "execute"
- `NEPH_SESSION_ID`: Current session identifier
- `NVIM_SOCKET`: Path to Neovim socket (for reverse RPC if needed)

**Protocol format:**
```bash
#!/usr/bin/env bash
# ~/.neph/tools/custom_tool

case "${NEPH_ACTION}" in
  describe)
    jq -n '{
      name: "custom_tool",
      description: "My custom tool",
      inputSchema: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" }
        },
        required: ["path"]
      }
    }'
    ;;
  execute)
    # Read JSON input from stdin
    INPUT=$(cat)
    PATH=$(echo "$INPUT" | jq -r '.path')
    # Do work
    echo "{\"result\": \"success\"}"
    ;;
esac
```

**Rationale:**
- Proven by Amp (Sourcegraph) in production
- Language-agnostic: any executable (Bash, Python, Node, Go, etc.)
- Simple debugging: run script with `NEPH_ACTION=describe` manually
- Stdin/stdout easier to test than complex RPC mocking

**Alternatives considered:**
- ❌ **Claude Code hooks format**: Too specific to lifecycle events, we need general tool protocol
- ❌ **MCP server protocol**: Too heavyweight, requires JSON-RPC server per script
- ❌ **Command-line arguments**: Limits input size, stdin cleaner for JSON

### 4. Testing Strategy

**Decision:** Three-tier testing pyramid:

**Unit tests (70%)** - Pure Lua, plenary.nvim:
```lua
-- tests/unit/api/write_spec.lua
describe("api.write", function()
  it("validates path is string", function()
    local write = require("neph.api.write")
    assert.has_error(function() write.file(nil, "content") end)
  end)
end)
```

**Integration tests (25%)** - Vitest + headless Neovim:
```typescript
// tests/integration/node-client.test.ts
import { attach } from "@neovim/node-client";
import { NephClient } from "@neph/client";

test("write file via RPC", async () => {
  const nvim = await attach({ socket: process.env.NVIM_SOCKET });
  const client = new NephClient(nvim);
  await client.writeFile("/tmp/test.txt", "hello");
  // Assert file exists via nvim API
});
```

**E2E tests (5%)** - Real agents:
```bash
# tests/e2e/pi-integration.sh
pi "Write a hello world to test.py"
# Assert test.py exists and contains expected code
```

**Rationale:**
- Pure Lua unit tests are fast, no external deps, cover 70% of logic
- Integration tests validate protocol adapters work with real Neovim
- E2E tests catch integration issues but are slow, keep to 5%

**Alternatives considered:**
- ❌ **Only e2e tests**: Too slow, hard to debug failures
- ❌ **No integration tests**: Would miss protocol serialization bugs
- ❌ **Manual testing only**: Not sustainable, no CI confidence

### 5. Migration Strategy

**Decision:** Phased rollout with feature flags per agent:

**Phase 1**: Pure Lua API layer (no breaking changes)
- Create `lua/neph/api/` with existing tool logic extracted
- Existing `tools.lua` calls new API internally
- No user-visible changes, 100% backward compatible

**Phase 2**: Protocol adapters + Node client
- Add `lua/neph/protocols/rpc.lua` and `@neph/client` package
- Pi agent can opt-in to new protocol via config: `{ protocol = "rpc" }`
- Python shim remains default for backward compatibility

**Phase 3**: WebSocket + Script protocols
- Add `lua/neph/protocols/websocket.lua` and `script.lua`
- Document protocol selection in agent config
- Provide migration guide for custom agents

**Phase 4**: Deprecate shim (future)
- Once all built-in agents migrated, mark shim as legacy
- Keep for backward compatibility but document alternatives

**Rationale:**
- No big-bang rewrite, each phase is deployable
- Users can test new protocols without breaking existing workflows
- Rollback is simple: revert to previous phase

## Risks / Trade-offs

### Risk: Protocol proliferation complexity
**Mitigation:** 
- Limit to 4 protocols (WebSocket, Script, RPC, Shim) initially
- Shared Lua API layer means adding protocols doesn't multiply implementation effort
- Protocol selection is agent config, not user-facing complexity

### Risk: WebSocket server resource usage
**Mitigation:**
- Server only runs when WebSocket protocol active
- Lockfile cleanup on Neovim exit (VimLeavePre autocmd)
- Connection limit (default 5 concurrent clients) to prevent resource exhaustion

### Risk: Script protocol security (arbitrary executables)
**Mitigation:**
- Only executables in `~/.neph/tools/` or `$NEPH_TOOLBOX` are discoverable
- Permission model (ask user before first execution of new script)
- Scripts run in same security context as user's terminal (no escalation)

### Risk: Testing complexity with multiple protocols
**Mitigation:**
- Pure Lua API layer means protocols share test coverage
- Protocol adapters have focused test scope (just transport logic)
- Integration tests use real Neovim socket, not protocol-specific mocking

### Risk: Breaking existing pi agent workflow
**Mitigation:**
- Shim remains default protocol until migration complete
- Pi agent can specify protocol: `{ protocol = "shim" }` to force old behavior
- Automated tests for backward compatibility on every PR

### Trade-off: Performance vs simplicity
**Decision:** Favor simplicity initially
- WebSocket server is single-threaded (no connection pooling)
- Script protocol spawns subprocess per call (no persistent process pool)
- Can optimize later if profiling shows bottlenecks

**Rationale:** Neovim plugins are I/O bound (file operations), not CPU bound. Simpler code is more maintainable and easier to test.

### Trade-off: Feature parity across protocols
**Decision:** Not all protocols support all features
- WebSocket: Event streaming (file changes, diagnostics)
- Script: Tool execution only (no events)
- RPC: Both tools and events
- Shim: Tools only (legacy)

**Rationale:** Each protocol optimized for its use case. Document capabilities per protocol in user guide.

## Migration Plan

### Deployment Steps

**Step 1: Pure Lua API layer**
1. Create `lua/neph/api/init.lua` with public exports
2. Extract write/edit/delete/read logic from existing code
3. Update `tools.lua` to call new API
4. Run full test suite, ensure no regressions
5. Tag release: `v1.0.0-api-layer`

**Step 2: Node client + RPC protocol**
1. Create `tools/client/` package with `@neph/client`
2. Implement `lua/neph/protocols/rpc.lua`
3. Add protocol selection to agent config
4. Update pi.ts to use `@neph/client` (opt-in via config)
5. Add integration tests for RPC protocol
6. Tag release: `v1.1.0-rpc-protocol`

**Step 3: WebSocket + Script protocols**
1. Implement `lua/neph/protocols/websocket.lua` with lockfile
2. Implement `lua/neph/protocols/script.lua` with toolbox discovery
3. Add lifecycle hooks (`lua/neph/hooks/`)
4. Document protocol selection in README
5. Add integration tests for new protocols
6. Tag release: `v1.2.0-multi-protocol`

**Step 4: Documentation + migration guide**
1. Update README with protocol comparison table
2. Create migration guide for custom agents
3. Add examples for each protocol in `examples/`
4. Publish blog post on architecture redesign
5. Tag release: `v2.0.0` (stable multi-protocol)

### Rollback Strategy

Each phase is independently revertable:
- **Phase 1 rollback**: Pure Lua API is internal refactor, no config changes needed
- **Phase 2 rollback**: Remove `protocol = "rpc"` from agent config, falls back to shim
- **Phase 3 rollback**: Remove WebSocket/Script protocol config, existing RPC/Shim work

Critical data (session history, agent config) stored in `vim.fn.stdpath("data")`, survives rollbacks.

## Open Questions

1. **WebSocket message format**: Use JSON-RPC 2.0 strictly, or custom JSON format?
   - **Leaning toward**: JSON-RPC 2.0 for future MCP compatibility
   
2. **Script toolbox directory**: Single directory (`~/.neph/tools/`) or multiple (`$NEPH_TOOLBOX` like Amp)?
   - **Leaning toward**: Multiple directories (project-local + user-global) for flexibility

3. **Protocol negotiation**: Should agents advertise multiple protocols and neph select best, or require explicit config?
   - **Leaning toward**: Explicit config initially, add auto-negotiation in future version

4. **Lifecycle hooks**: Which events to support in initial implementation?
   - **Proposed**: session_start, session_end, pre_tool, post_tool (minimal set)
   - **Future**: Add more events (file_changed, diagnostics_updated) as needed

5. **Backward compatibility timeline**: How long to maintain Python shim as default?
   - **Proposed**: Keep as default for 2 major versions (v1.x, v2.x), deprecate in v3.0
