## Context

The integration layer connecting agents to the review system has multiple silent failure points. Users experience "review just doesn't work" without any indication of what's wrong. The root causes are: missing build artifacts, no timeouts on blocking promises, swallowed I/O errors, and silent fallback paths.

## Goals / Non-Goals

**Goals:**
- Every failure in the review chain produces a user-visible notification
- No infinite hangs — all async waits have timeouts
- File I/O errors in post-write review are surfaced, not swallowed
- Companion sidecar retries with backoff instead of infinite loop
- Gate timeout is distinguishable from user rejection

**Non-Goals:**
- Auto-fixing failures (just surface them)
- Changing the review protocol schema version
- Adding new review modes or agent types
- Modifying the install system itself (just surfacing its failures better)

## Decisions

### 1. Companion missing script: vim.notify ERROR
When `tools/gemini/dist/companion.js` doesn't exist, show `vim.notify("Neph: Gemini companion not built — run :NephTools install gemini", ERROR)` instead of debug log. Single notification, not repeated.

**Alternative considered:** Auto-triggering build — rejected because build is async and could fail, adding another failure path during session open.

### 2. NephClient.review() timeout: 5 minutes
Match the gate timeout (300s). Return a reject envelope with `reason: "timeout"`. The timeout is on the TypeScript promise, not the Lua side.

**Alternative considered:** Shorter timeout — rejected because large file reviews legitimately take several minutes.

### 3. Post-write I/O error handling: notify + early return
In `_apply_post_write`, if io.open fails, call `vim.notify(WARN)` and return early. Don't proceed with buffer/disk sync. The review is already complete in the queue — the user just needs to know the apply step failed.

### 4. Bus fallback notification: one-time per agent
Track a `notified_fallback` set in session.lua. When `bus.is_connected()` returns false for an extension agent, show WARN once: "Neph: {agent} bus disconnected, using terminal". Reset the flag when agent re-registers.

### 5. Gate exit codes: 0=pass, 1=error, 2=reject, 3=timeout
Add exit code 3 for timeout. The timeout envelope includes `{ decision: "timeout", reason: "Review timed out (300s)" }`. Agents can check the decision field to distinguish timeout from rejection.

### 6. Respawn backoff: 2s × 2^attempt, cap at 3 retries
Replace the fixed 2s delay with `2000 * 2^attempt`. After 3 failures (2s, 4s, 8s), stop retrying and show ERROR: "Neph: Gemini companion failed to start after 3 attempts".

### 7. Post-write channel_id: nil instead of 0
fs_watcher reviews have no CLI caller. Use `channel_id = nil` and skip the `vim.rpcnotify` call in `write_result` when channel_id is nil.

### 8. RPC error context: debug.traceback
Wrap the pcall error with `debug.traceback()` when the error is a string. Truncate to 500 chars to prevent oversized responses.

## Risks / Trade-offs

- [Notifications could be noisy if sidecar fails repeatedly] → Mitigated by one-time notification pattern and retry cap
- [Gate exit code 3 is a protocol change] → Low risk: agents already handle unknown exit codes as errors, and code 3 is additive
- [5-minute timeout may be too long for quick reviews] → Acceptable: matches existing gate timeout, shorter would risk false positives
