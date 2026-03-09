## Why

Gemini CLI currently integrates with neph.nvim via BeforeTool hooks that intercept `write_file`/`edit_file` and pipe them through `neph gate`. This works but is fragile—it depends on hook timing, stdin JSON parsing, and exit code semantics. Gemini CLI now offers a first-class IDE companion spec that uses MCP over HTTP for structured communication, including a dedicated diffing interface with `openDiff`/`closeDiff` tools and `diffAccepted`/`diffRejected` notifications. Building a proper companion integration gives us a stable, bidirectional channel with richer capabilities (context sharing, lifecycle management) and eliminates the hook→gate→exit-code indirection.

## What Changes

- **New MCP HTTP server** running inside Neovim (via a TypeScript sidecar process) that implements the Gemini IDE companion spec
- **Implements `openDiff` / `closeDiff` MCP tools** that route to neph's existing review engine for interactive hunk-by-hunk review
- **Sends `ide/diffAccepted` / `ide/diffRejected` notifications** back to Gemini CLI when the user resolves a review
- **Sends `ide/contextUpdate` notifications** with open files, cursor position, and selection context
- **Discovery file management**: writes/cleans up `gemini-ide-server-{PID}-{PORT}.json` in `os.tmpdir()/gemini/ide/`
- **Bearer token auth** on all incoming MCP requests
- **Gemini agent type changes** from `"hook"` to `"extension"` — hook-based settings.json merge is removed
- **BREAKING**: Gemini no longer uses `neph gate`; the companion server replaces the entire hook integration

## Capabilities

### New Capabilities
- `gemini-companion-server`: MCP HTTP server implementing the Gemini IDE companion spec (discovery, auth, transport)
- `gemini-diff-bridge`: Maps `openDiff`/`closeDiff` MCP tools to neph's review engine and sends `diffAccepted`/`diffRejected` notifications
- `gemini-context-provider`: Sends `ide/contextUpdate` notifications with workspace state (open files, cursor, selection)

### Modified Capabilities
- `agent-bus`: Gemini transitions from hook-based to extension-based agent, requiring bus registration for the companion sidecar

## Impact

- **Lua**: `lua/neph/agents/gemini.lua` — agent type changes from `hook` to `extension`, tools config updated
- **TypeScript**: New companion server in `tools/gemini/` — MCP HTTP server, diff bridge, context provider
- **Removed**: `tools/gemini/settings.json` (hook config no longer needed)
- **Gate schemas**: `gemini` schema in `tools/neph-cli/src/gate.ts` becomes dead code for Gemini (retained for backward compat or removed)
- **Dependencies**: MCP SDK (`@modelcontextprotocol/sdk` or lightweight HTTP handler), existing `neovim` npm package
- **protocol.json**: No changes needed — companion uses existing `review.open` RPC method via NephClient
- **User-facing**: Users must have Gemini CLI version that supports the IDE companion spec; companion server starts automatically when Gemini agent is launched
