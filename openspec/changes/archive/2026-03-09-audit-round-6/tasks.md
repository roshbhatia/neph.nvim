## 1. Post-write file write error checking

- [x] 1.1 In `review/init.lua:_apply_post_write`, check f:write() return in reject path (line ~160) — on error, close file, notify, return early
- [x] 1.2 In `review/init.lua:_apply_post_write`, check f:write() return in partial merge path (lines ~169-171) — on error, close file, notify, return early

## 2. Backend nil guard

- [x] 2.1 In `session.lua`, add `if not backend then return end` guard at top of `M.open()` (focus, hide, kill_session, get_info already have guards)

## 3. HTTP body byte-accurate size limit

- [x] 3.1 In `server.ts`, track body size using `Buffer.byteLength(chunk)` instead of `body.length`

## 4. JSON-RPC error response format

- [x] 4.1 In `server.ts` tool handler catch block, return proper JSON-RPC error object `{ code: -32603, message }` instead of `{ content, isError }`

## 5. closeDiff param validation

- [x] 5.1 In `diff_bridge.ts:closeDiff`, change filePath validation to `typeof filePath !== "string"` to match openDiff pattern

## 6. readStdin error handling

- [x] 6.1 In `index.ts`, add `.catch()` to outer `readStdin().then()` chain
