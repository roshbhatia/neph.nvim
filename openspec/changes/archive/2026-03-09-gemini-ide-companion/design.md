## Context

Gemini CLI supports an IDE companion spec where editors run a local MCP HTTP server. Gemini CLI discovers this server via port files in `os.tmpdir()/gemini/ide/`, authenticates with bearer tokens, and uses MCP tools (`openDiff`, `closeDiff`) plus notifications (`ide/diffAccepted`, `ide/diffRejected`, `ide/contextUpdate`) for structured bidirectional communication.

Currently Gemini integrates with neph via BeforeTool hooks → `neph gate` CLI → exit codes. This is indirect and can't support richer features like context sharing or server-initiated notifications.

neph.nvim already has:
- A review engine (`lua/neph/api/review/`) with hunk-by-hunk accept/reject
- An agent bus (`lua/neph/internal/bus.lua`) for extension agents
- NephClient SDK (`tools/lib/neph-client.ts`) for persistent socket connections to Neovim
- A build/install system (`lua/neph/tools.lua`) for TypeScript sidecar processes

## Goals / Non-Goals

**Goals:**
- Implement a Gemini IDE companion server as a TypeScript sidecar that neph manages
- Map `openDiff`/`closeDiff` MCP tools to neph's existing review engine
- Send `ide/diffAccepted`/`ide/diffRejected` notifications back to Gemini CLI
- Send `ide/contextUpdate` with open files, cursor, and selection from Neovim
- Handle discovery file lifecycle (create on start, clean up on exit)
- Transition Gemini from hook-based to extension-based agent

**Non-Goals:**
- Implementing the full MCP spec generically — only the subset Gemini CLI needs
- Supporting multiple simultaneous Gemini CLI sessions from one companion
- Adding context features beyond what the companion spec defines (no custom tools)
- Building a reusable MCP server library — this is Gemini-specific

## Decisions

### 1. TypeScript sidecar process (not embedded in Neovim)

The companion server must run an HTTP server. Neovim's Lua runtime has no production-quality HTTP server capabilities. A TypeScript sidecar fits the established pattern (Pi extension, neph-cli) and can use the existing NephClient SDK.

**Alternative**: LuaSocket or libuv HTTP in Neovim. Rejected — fragile, limited HTTP support, and breaks the established pattern where all network-facing code lives in TypeScript.

### 2. Lightweight HTTP handler with MCP message framing (not full MCP SDK)

The Gemini companion spec uses MCP-over-HTTP but only requires 2 tools and 3 notification types. Using the full `@modelcontextprotocol/sdk` would add a heavy dependency for minimal benefit. Instead, implement a thin HTTP handler that speaks JSON-RPC 2.0 (MCP's wire format) with just the needed methods.

**Alternative**: `@modelcontextprotocol/sdk`. Reconsidered if the spec grows, but currently overkill.

### 3. Sidecar lifecycle managed by neph (auto-start/stop)

The companion server starts when the Gemini terminal session opens and stops when it closes. neph's `init.lua` already manages tool builds; the companion process is spawned via `vim.fn.jobstart()` and tracked alongside the terminal session.

Lua spawns the sidecar, passing `NVIM_SOCKET_PATH` and workspace root. The sidecar:
1. Starts HTTP server on port 0
2. Connects to Neovim via NephClient, registers as "gemini" on the bus
3. Writes discovery file to `os.tmpdir()/gemini/ide/`
4. Handles MCP requests until terminated
5. Cleans up discovery file on exit

### 4. Review flow: openDiff → review.open RPC → notification on resolve

When Gemini CLI calls `openDiff(filePath, newContent)`:
1. Companion calls `neph.review(filePath, newContent)` via NephClient
2. Neovim opens vimdiff, user reviews hunks
3. NephClient returns ReviewEnvelope
4. If accepted (decision = "accept" or "partial"): companion sends `ide/diffAccepted` notification with final content
5. If rejected: companion sends `ide/diffRejected` notification
6. `openDiff` tool returns success/failure to Gemini CLI

`closeDiff` reads the file's current content from disk and returns it, then clears any pending review state.

### 5. Context updates via Neovim autocmds → sidecar notification

The sidecar registers a custom RPC notification (`neph:context`) that the Lua side sends on `BufEnter`, `CursorMoved`, and `CursorHold` (debounced). The Lua module collects open buffers, cursor position, and visual selection, then pushes to the sidecar channel. The sidecar forwards this as `ide/contextUpdate` to Gemini CLI.

### 6. Auth token: random UUID generated per session

The sidecar generates a crypto-random UUID as the bearer token on startup and writes it to the discovery file. All incoming HTTP requests are validated against this token.

## Risks / Trade-offs

- **[Risk] Gemini CLI companion spec is new and may change** → The thin HTTP handler approach minimizes coupling; changes require updating a small surface area. Pin to current spec version in comments.

- **[Risk] Sidecar process management adds complexity** → Mitigated by following the Pi extension pattern (jobstart + SIGTERM cleanup). The bus health timer already handles dead channel detection.

- **[Risk] Port collisions or stale discovery files** → Port 0 assignment eliminates collisions. Discovery file cleanup on process exit (SIGTERM, SIGINT handlers) + VimLeavePre cleanup in Lua. Stale files have PID embedded — Gemini CLI can verify process liveness.

- **[Trade-off] Context updates require new autocmds** → Adds BufEnter/CursorMoved/CursorHold handlers, but these are standard and cheap. Debounce at 50ms matches the spec recommendation.

- **[Trade-off] Removes hook-based fallback** → Users on older Gemini CLI versions without companion support lose neph integration. Mitigated by documenting minimum Gemini CLI version requirement.
