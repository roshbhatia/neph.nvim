## 1. Agent Definition Update

- [x] 1.1 Change `lua/neph/agents/gemini.lua` type from `"hook"` to `"extension"`, remove the merges tools config, add builds/symlinks for the companion sidecar
- [x] 1.2 Remove `tools/gemini/settings.json` (hook config no longer needed)
- [x] 1.3 Remove the `gemini` schema entry from `tools/neph-cli/src/gate.ts` (no longer used for gate interception)

## 2. Companion Sidecar Scaffold

- [x] 2.1 Create `tools/gemini/package.json` with dependencies: `neovim` (npm), TypeScript tooling, shared lib reference
- [x] 2.2 Create `tools/gemini/src/companion.ts` entry point: parse CLI args (workspace root), initialize NephClient connection, register as "gemini" on bus, start HTTP server
- [x] 2.3 Add build config (`tsconfig.json`, build script) following the Pi extension pattern

## 3. MCP HTTP Server

- [x] 3.1 Implement HTTP server in `tools/gemini/src/server.ts`: listen on port 0, accept POST requests, parse JSON-RPC 2.0 messages, route to tool handlers
- [x] 3.2 Implement bearer token auth middleware: generate crypto-random UUID on startup, validate `Authorization: Bearer {token}` on every request, reject with 401 on mismatch
- [x] 3.3 Implement discovery file management: write `gemini-ide-server-{PID}-{PORT}.json` to `os.tmpdir()/gemini/ide/` on startup, delete on SIGTERM/SIGINT/exit
- [x] 3.4 Implement MCP tool listing: respond to `tools/list` with `openDiff` and `closeDiff` tool definitions

## 4. Diff Bridge (openDiff / closeDiff)

- [x] 4.1 Implement `openDiff` handler: extract `filePath` and `newContent` from MCP tool call, call `neph.review(filePath, newContent)`, return empty content on success or error on failure
- [x] 4.2 Implement `closeDiff` handler: read file content from disk, return as TextContent block
- [x] 4.3 Implement diff notification dispatch: after ReviewEnvelope resolves, send `ide/diffAccepted` (with filePath + content) on accept/partial, or `ide/diffRejected` (with filePath) on reject
- [x] 4.4 Implement file write on accept: write final content to disk after accepted review, call `neph.checktime()` to refresh buffers

## 5. Context Provider

- [x] 5.1 Create `lua/neph/internal/companion.lua` module: collect open buffers (path, timestamp, isActive), cursor position, visual selection; push via `vim.rpcnotify(channel, "neph:context", data)` to gemini bus channel
- [x] 5.2 Register autocmds (BufEnter, CursorHold) in companion module with 50ms debounce to trigger context collection and push
- [x] 5.3 Handle `neph:context` notification in companion sidecar: forward as `ide/contextUpdate` MCP notification to Gemini CLI

## 6. Sidecar Lifecycle Management

- [x] 6.1 Add sidecar spawn logic to neph's session/init: on Gemini terminal open, `vim.fn.jobstart()` the companion sidecar with `NVIM_SOCKET_PATH` and workspace root env vars
- [x] 6.2 Add sidecar termination on Gemini session close: SIGTERM the job, clean up on VimLeavePre
- [x] 6.3 Add crash respawn: detect unexpected sidecar exit via `on_exit` callback, respawn after brief delay if Gemini session still active

## 7. Testing

- [x] 7.1 Add Vitest tests for HTTP server: JSON-RPC routing, auth validation, error responses
- [x] 7.2 Add Vitest tests for diff bridge: openDiff/closeDiff handlers with mocked NephClient
- [x] 7.3 Add Vitest tests for discovery file lifecycle: creation, content schema, cleanup
- [x] 7.4 Add Lua plenary tests for companion context collection: buffer list, cursor, selection formatting
- [x] 7.5 Manual integration test: launch Gemini CLI with companion, verify diff review round-trip
