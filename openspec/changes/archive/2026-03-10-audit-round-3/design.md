## Approach

Targeted point fixes — each finding is a standalone 1-5 line change. No architectural changes needed.

## Key Decisions

### Operator precedence fix
Change `not envelope.content:sub(-1) == "\n"` to `envelope.content:sub(-1) ~= "\n"`. The `not` operator binds tighter than `==` in Lua, so the existing code evaluates `(not envelope.content):sub(-1)` which errors.

### String.replace → replaceAll
JavaScript `.replace(string, string)` only replaces the first occurrence. Use `replaceAll()` (available in Node 15+, which is well within our baseline). Affects `reconstructEdit()` in gate.ts, and the equivalent edit reconstruction in opencode/edit.ts and amp/neph-plugin.ts.

### Timer close in fs_watcher
The debounce timer callback sets `debounce_timers[filepath] = nil` but never calls `timer:close()`. Add `timer:stop(); timer:close()` before nilling. The stop is needed because the timer might fire between creation and the callback.

### uiSelect/uiInput timeout
Add 60s timeout matching the pattern already used in `review()`. On timeout, delete from `pendingRequests` and resolve with `undefined` (same as user-cancelled).

### fs.watch error handler
Add `watcher.on('error', ...)` that logs to stderr and doesn't crash the process. The watcher is best-effort — notifications also handle result delivery.

### Engine bounds check
In `review/engine.lua` finalize, clamp `j` to `#new_lines` when iterating accepted hunk lines. If hunk metadata is inconsistent, this prevents nil insertion into the result.

### Server body size limit
Track accumulated body length in the for-await loop. If it exceeds 1MB, destroy the request stream and respond 413.

### Dead code removal
Remove `unmap_keymaps` in review/ui.lua — it's defined but never called.

### Wezterm job_id notification
When `job_id <= 0` in session.send(), add `vim.notify(WARN)` so the user knows the prompt didn't reach the agent.

## Files Changed

| File | Change |
|------|--------|
| `lua/neph/api/review/init.lua` | Fix `not x == y` → `x ~= y` |
| `lua/neph/api/review/engine.lua` | Bounds check on `new_lines[j]` |
| `lua/neph/api/review/ui.lua` | Remove dead `unmap_keymaps` |
| `lua/neph/internal/fs_watcher.lua` | Close timer before nil |
| `lua/neph/internal/session.lua` | Notify on failed wezterm job |
| `tools/neph-cli/src/gate.ts` | `replaceAll()`, fs.watch error |
| `tools/neph-cli/src/index.ts` | fs.watch error handler |
| `tools/opencode/edit.ts` | `replaceAll()` |
| `tools/amp/neph-plugin.ts` | `replaceAll()` |
| `tools/gemini/src/server.ts` | Body size limit |
| `tools/lib/neph-client.ts` | uiSelect/uiInput timeout |
