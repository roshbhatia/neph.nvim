## Why

Sixth e2e audit found silent data loss risk in post-write review (f:write errors unchecked), crash risk from premature API calls before backend initialization, a body size limit bypass in the Gemini MCP server, JSON-RPC error response format violation, and minor validation gaps. These are correctness and robustness issues in core review and server paths.

## What Changes

- Check f:write() return values in `_apply_post_write` and handle errors (data loss prevention)
- Add backend nil guards in session.lua public functions (crash prevention)
- Track HTTP body size in bytes instead of characters in gemini server.ts (DoS fix)
- Fix JSON-RPC error response format in server.ts tool handler catch block
- Add typeof validation on closeDiff filePath parameter in diff_bridge.ts
- Add .catch() on readStdin() promise chain in index.ts

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `review-protocol`: f:write() error checking in post-write apply path
- `gemini-companion-server`: HTTP body byte-accurate size limit, JSON-RPC error format, closeDiff param validation
- `neph-cli`: readStdin() promise error handling

## Impact

- `lua/neph/api/review/init.lua` — write error checking in _apply_post_write
- `lua/neph/internal/session.lua` — backend nil guards
- `tools/gemini/src/server.ts` — byte-based body limit, JSON-RPC error format
- `tools/gemini/src/diff_bridge.ts` — closeDiff filePath validation
- `tools/neph-cli/src/index.ts` — readStdin catch
