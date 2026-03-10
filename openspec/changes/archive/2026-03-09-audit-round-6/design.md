## Context

Audit round 6 found data integrity risks in file write paths, a missing initialization guard, and HTTP/protocol-level issues in the Gemini MCP server.

## Goals / Non-Goals

**Goals:**
- Prevent silent data loss when f:write() fails during post-write review apply
- Prevent crashes when session.lua functions are called before setup()
- Fix body size limit to count bytes not characters (multi-byte UTF-8 bypass)
- Fix JSON-RPC error response to use proper error object format
- Consistent param validation in closeDiff handler
- Catch readStdin() rejections

**Non-Goals:**
- Refactoring session.lua initialization flow
- Adding retry logic for failed writes
- Rewriting the MCP server

## Decisions

1. **f:write() error checking**: Wrap each write in error check. On failure, close the file, notify the user, and return early. Don't attempt partial recovery — the user can re-run the review.

2. **Backend nil guard**: Add a single early-return guard `if not backend then return end` at the top of each public session.lua function that uses backend. Return nil/false as appropriate for the function signature.

3. **Byte-accurate body limit**: Use `Buffer.byteLength(chunk)` to track incoming bytes. This correctly handles multi-byte UTF-8 characters that could bypass a character-count limit.

4. **JSON-RPC error format**: Return a proper JSON-RPC error object `{ code: -32603, message: ... }` instead of the tool result format `{ content, isError }`. Code -32603 is "Internal error" per JSON-RPC spec.

5. **closeDiff validation**: Match openDiff pattern — use `typeof filePath !== "string"` instead of bare falsy check.

6. **readStdin catch**: Add `.catch()` to the outer `readStdin().then()` promise chain.

## Risks / Trade-offs

- The backend nil guard adds minor overhead per call but prevents hard crashes — acceptable.
- Changing the JSON-RPC error format is technically a behavior change for Gemini CLI consumers, but the current format is wrong per spec, so this is a bugfix.
