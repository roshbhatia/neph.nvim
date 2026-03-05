## Context

**Current State:**
- Single Python subprocess shim (shim.py) is the only integration point
- Tools overridden in pi.ts extension via pi coding-agent hooks
- Blocking shell execution model limits concurrency
- Testing requires complex mocking of subprocess and msgpack protocol
- No event streaming capability (file changes, diagnostics must be polled)

**Research Findings:**
1. **amp.nvim** (Sourcegraph): Pure Lua WebSocket server using `vim.loop`, lockfile discovery, event-driven architecture
2. **claudecode.nvim** (Coder): WebSocket + MCP protocol (JSON-RPC 2.0), 12 MCP tools
3. **Amp toolboxes**: Executables in `$AMP_TOOLBOX` directories, stdin/stdout protocol with describe/execute actions
4. **Claude Code hooks**: Shell commands at lifecycle events with JSON input/output

**Key Insight:**
No users exist yet (pre-1.0) - we can design the **right** architecture without migration complexity. Focus on:
- **Testability**: Pure functions, clear boundaries, no hidden state
- **Composability**: Protocols as adapters, tools as Lua functions with optional protocol layers
- **Readability**: Obvious data flow, minimal indirection
- **Graceful degradation**: Protocol unavailable? Clear error and fallback suggestions

**Constraints:**
- Neovim ≥ 0.10 required
- Dependencies chosen for quality, not minimalism - we control the stack
- Can require Node, Python, or any runtime that makes the architecture better
- Prioritize developer experience and code quality over dependency count

## Goals / Non-Goals

**Goals:**
- **Clean architecture**: Pure Lua API → Protocol adapters → Language clients (3 clear layers)
- **Primary protocol is RPC**: Direct Neovim connection via @neovim/node-client (Node is a dependency - that's fine)
- **Quality tests, not coverage**: Unit tests for fast feedback, integration tests for real behavior, minimal e2e
- **Best tools for the job**: Use whatever language/library makes code clearest and most testable
- **Composability**: Tools are Lua functions, protocol adapters are interchangeable, hooks extend at boundaries
- **Readable**: Obvious data flow, minimal magic, clear error messages

**Non-Goals:**
- Minimizing dependencies (quality > dependency count)
- Supporting environments without Node/Python/modern tooling
- Backward compatibility (pre-1.0, no users - clean break enabled)
- Supporting 4+ protocols initially (start with RPC, add Script if needed)
- Generic MCP server (focus on neph-specific needs)
- Migration complexity (no migration - fresh start)
- Achieving specific coverage percentages (focus on test quality over quantity)

## Decisions

### 1. Clean Three-Layer Architecture

**Decision:** Strict layering with clear boundaries:
```
┌─────────────────────────────────────────────────────────┐
│  Layer 3: Language Clients                              │
│  - @neph/client (TypeScript + @neovim/node-client)     │
│  - Shell scripts (optional, for Amp toolbox pattern)   │
└─────────────────────────────────────────────────────────┘
                          ↓ RPC / Stdio
┌─────────────────────────────────────────────────────────┐
│  Layer 2: Protocol Adapters (Lua)                      │
│  - lua/neph/protocols/rpc.lua (primary)                │
│  - lua/neph/protocols/script.lua (optional)            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Pure Lua API (Single Source of Truth)        │
│  - lua/neph/api/write.lua                               │
│  - lua/neph/api/edit.lua                                │
│  - lua/neph/api/delete.lua                              │
│  - lua/neph/api/read.lua                                │
└─────────────────────────────────────────────────────────┘
```

**Rationale:**
- **Layer 1 (Lua API)** is pure, testable without external deps, single source of truth
- **Layer 2 (Protocol Adapters)** translates protocol-specific input to Lua API calls
- **Layer 3 (Language Clients)** handles transport, thin wrappers over protocol
- No cross-layer leakage: protocols don't know about language clients, API doesn't know about protocols

**Alternatives considered:**
- ❌ **Monolithic design**: All logic in one layer → hard to test, change, understand
- ❌ **Protocol logic in clients**: Would duplicate validation/error handling across clients
- ❌ **No adapter layer**: Direct calls from clients to API → tight coupling, can't swap protocols

### 2. RPC as Primary Protocol

**Decision:** RPC via `@neovim/node-client` is the default and recommended protocol. No Python subprocess.

**Rationale:**
- Direct Neovim connection → no subprocess overhead, no serialization complexity
- `@neovim/node-client` is mature, battle-tested, well-documented
- TypeScript client enables type-safe agent development
- Synchronous RPC calls for file operations are appropriate (they're I/O bound anyway)
- Can subscribe to Neovim events natively (autocmds, diagnostics) if needed later

**Implementation:**
```typescript
// tools/client/src/index.ts
import { attach } from "@neovim/node-client";

export class NephClient {
  async writeFile(path: string, content: string): Promise<void> {
    await this.nvim.lua(`require("neph.api.write").file(${path}, ${content})`);
  }
}
```

**Alternatives considered:**
- ❌ **WebSocket primary**: Adds complexity (server, lockfile, JSON-RPC), only needed if streaming events
- ❌ **Python shim**: Subprocess overhead, serialization overhead, harder to debug
- ❌ **HTTP server**: Even more overhead than WebSocket, not needed for local editor

### 3. Script Protocol as Optional

**Decision:** Support Amp toolbox-style scripts (`NEPH_ACTION=describe/execute`, stdin/stdout) as optional protocol for shell-based agents.

**Rationale:**
- Proven pattern (Amp uses in production)
- Language-agnostic: bash, python, node, go, rust - anything executable
- Simple debugging: run script manually with `NEPH_ACTION=describe`
- Some agents (like goose) might prefer shell scripts over Node RPC

**When to use:**
- Agent is primarily shell-based (bash/zsh workflows)
- Agent already has executable scripts
- Team prefers shell scripts over TypeScript/Node

**When NOT to use:**
- Agent is already in Node/TypeScript → use RPC directly
- Need fast iteration → RPC has less overhead than spawning subprocess

**Alternatives considered:**
- ❌ **No script support**: Would force all agents to Node, limits flexibility
- ❌ **Script as primary**: Subprocess overhead for every tool call, slower than RPC

### 4. Quality-Focused Testing Strategy

**Decision:** Write tests that give **confidence**, not just coverage.

**Unit Tests (Lua with plenary):**
- Test pure Lua API functions
- Fast (< 100ms for full unit suite)
- No external dependencies (no Node, Python, network)
- Focus: **Does the API do what it claims?**

Example:
```lua
describe("api.write", function()
  it("writes content to file", function()
    local tmpfile = vim.fn.tempname()
    require("neph.api.write").file(tmpfile, "hello")
    assert.equals("hello", vim.fn.readfile(tmpfile)[1])
  end)
end)
```

**Integration Tests (TypeScript with vitest):**
- Test protocol adapters with real Neovim instance
- Spawn headless Neovim, connect via RPC, verify operations
- Focus: **Does the protocol adapter translate correctly?**

Example:
```typescript
test("RPC protocol writes file", async () => {
  const nvim = await spawnHeadlessNvim();
  const client = new NephClient(nvim);
  await client.writeFile("/tmp/test.txt", "hello");
  const content = await fs.readFile("/tmp/test.txt", "utf-8");
  expect(content).toBe("hello");
});
```

**E2E Tests (Shell scripts with real agents):**
- Test complete user workflows
- Run real agent (pi, goose) with test prompts
- Focus: **Does it work end-to-end for users?**
- Keep minimal (slow, brittle, hard to debug)

Example:
```bash
# tests/e2e/pi-write-file.sh
pi "Write 'hello world' to test.py"
grep "hello world" test.py || exit 1
```

**Rationale:**
- Coverage percentage is a **proxy** for confidence, not the goal itself
- 10 meaningful tests > 100 tests hitting every line but missing real bugs
- Fast unit tests → rapid feedback during development
- Integration tests catch protocol issues (serialization, RPC errors, etc.)
- E2E tests catch UX issues but are expensive - keep minimal

**Alternatives considered:**
- ❌ **Coverage targets**: Incentivizes gaming the metric (useless tests to hit %)
- ❌ **Only e2e tests**: Too slow, too brittle, hard to debug failures
- ❌ **Only unit tests**: Miss protocol integration bugs, serialization issues

### 5. No Migration, Clean Break

**Decision:** This is v1.0 of neph.nvim. No backward compatibility. No migration guide. Fresh start.

**Rationale:**
- Pre-1.0, no users exist yet
- Migration complexity is **technical debt** we don't need to carry
- Clean break enables clean design
- Can make breaking changes during v1.x alphas/betas until API stabilizes

**What this enables:**
- Rename/remove/redesign anything without guilt
- Remove Python shim completely (no gradual deprecation)
- Remove pi.ts extension override pattern (replace with RPC registry)
- Simplify config schema (no legacy `shim_timeout`, `shim_path` fields)

**Alternatives considered:**
- ❌ **Backward compat**: Carrying migration code forever, complicates every decision
- ❌ **Gradual deprecation**: Wastes time building migration layers nobody needs

### 6. Graceful Degradation

**Decision:** When protocol is unavailable, fail with **clear error** and suggest alternatives. No silent failures.

**Example scenarios:**

**RPC protocol unavailable (no Node):**
```lua
-- Error message
"neph: RPC protocol requires Node.js and @neph/client package.
Install: npm install -g @neph/client
Or use script protocol: { protocol = 'script' }"
```

**Script not executable:**
```lua
"neph: Script '/Users/you/.neph/tools/custom_tool' is not executable.
Fix: chmod +x /Users/you/.neph/tools/custom_tool"
```

**Socket not found:**
```lua
"neph: Could not find Neovim socket. Is neph.nvim loaded?
Check: :lua vim.print(vim.v.servername)"
```

**Rationale:**
- Debugging time is **expensive** - good errors save hours
- "It doesn't work" → 30 minutes of debugging
- Clear error → 30 seconds to fix
- Suggest actionable fix in every error message

**Alternatives considered:**
- ❌ **Silent fallback**: User doesn't know what happened, can't fix it
- ❌ **Generic errors**: "RPC failed" → user doesn't know how to fix

### 7. Hooks for Extensibility

**Decision:** Provide lifecycle hooks at **boundaries** (session start/end, pre/post tool). No hooks in the middle of API functions.

**Hook points:**
- `session_start`: When agent session begins
- `session_end`: When agent session ends
- `pre_tool`: Before tool execution (can modify input or cancel)
- `post_tool`: After tool execution (can inspect result)

**What hooks CANNOT do:**
- Modify API internals
- Hook into middle of file write operation
- Override protocol adapter behavior

**Rationale:**
- Hooks at boundaries → predictable extension points
- Hooks in the middle → fragile, breaks refactoring, hard to reason about
- Claude Code hooks pattern: proven, simple, extensible

**Example use case:**
```lua
-- ~/.neph/hooks/log_writes.lua
return function(event, context)
  if event == "post_tool" and context.tool == "write_file" then
    log.info("Wrote file: " .. context.args.path)
  end
end
```

**Alternatives considered:**
- ❌ **No hooks**: Hard to extend, users resort to monkey-patching
- ❌ **Hooks everywhere**: Fragile, hard to maintain, breaks refactoring

### 8. Embrace Quality Dependencies

**Decision:** Choose dependencies that make code **better** - clearer, more testable, more maintainable.

**Good dependencies to embrace:**
- `@neovim/node-client`: Battle-tested RPC library
- `zod`: Runtime validation for protocol messages (type-safe parsing)
- `vitest`: Modern, fast test runner with great DX
- `plenary.nvim`: Standard Lua test/async library for Neovim
- Whatever else makes sense for quality

**Bad dependencies to avoid:**
- Abandoned packages
- Packages with unclear purpose ("utils", "helpers")
- Dependencies that hide complexity rather than manage it

**Rationale:**
- You're the user - if Node/Python/etc. make dev experience better, use them
- Fewer dependencies ≠ better code (sometimes it means reinventing wheels poorly)
- Well-maintained dependencies are **assets**, not liabilities
- Ship `flake.nix` with all dev dependencies - reproducible environment

**Example:**
```typescript
// Use zod for protocol validation - clear, type-safe, runtime errors
import { z } from "zod";

const WriteFileRequest = z.object({
  path: z.string(),
  content: z.string(),
});

// Parse and validate in one line, get TypeScript types automatically
const req = WriteFileRequest.parse(rawInput);
```

**Alternatives considered:**
- ❌ **Minimize dependencies**: Leads to NIH syndrome, reinventing validation, testing, etc.
- ❌ **No validation**: Runtime errors are cryptic, hard to debug

## Risks / Trade-offs

### Risk: Breaking everything with clean slate
**Mitigation:** Pre-1.0, no users - this is the **right time** for clean break. After 1.0, commit to stability.

### Risk: RPC requires Node runtime
**Not a risk:** You're the user, Node is fine. Ship with `flake.nix` devshell that includes Node. Users who can install Neovim plugins can install Node.

### Risk: Less protocol diversity than original design
**Decision:** Start with 2 protocols (RPC, Script), add WebSocket later if streaming events needed. **YAGNI** - don't build features we don't need yet.

### Trade-off: No Python shim option
**Decision:** If agent needs Python, use script protocol with Python script. No special subprocess model for Python.

### Trade-off: Fewer tests initially
**Decision:** Focus on quality over quantity. 20 meaningful tests > 100 meaningless tests for coverage.

## Open Questions

1. **WebSocket protocol timing**: Add in v1.0 or defer to v1.1+ if no agent needs streaming events?
   - **Leaning toward**: Defer - YAGNI, can add later if needed

2. **Hook configuration**: File-based discovery (`~/.neph/hooks/`) or config-based only?
   - **Leaning toward**: File-based discovery (convention over configuration)

3. **Tool registry**: Global or per-protocol?
   - **Leaning toward**: Per-protocol with shared interface

4. **Error types**: Custom error classes in Lua or just strings?
   - **Leaning toward**: Strings with consistent format (Lua doesn't have great error class support)
